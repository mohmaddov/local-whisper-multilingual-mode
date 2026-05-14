import Foundation
import os.log

private let logger = Logger(subsystem: "com.localwhisper.app", category: "KnowledgeBase")

/// Generates and maintains the knowledge base from ledger entries
actor KnowledgeBaseService {
    private let ledgerService: LedgerService
    private let tagService: TagExtractionService
    private var baseURL: URL
    private var refreshTask: Task<Void, Never>?
    
    // Cache of extracted tags per entry ID (persisted to avoid re-processing)
    private var tagCache: [UUID: [String]] = [:]
    private let tagCacheURL: URL
    
    // State
    private(set) var lastRefresh: Date?
    private(set) var isRebuilding = false
    private(set) var lastError: String?
    
    init(
        ledgerService: LedgerService,
        tagService: TagExtractionService,
        basePath: URL? = nil
    ) {
        self.ledgerService = ledgerService
        self.tagService = tagService
        self.baseURL = basePath ?? Self.defaultBasePath
        self.tagCacheURL = self.baseURL.appendingPathComponent(".tag_cache.json")
        
        // Defer actor-isolated initialization
        Task { await self.initialize() }
    }
    
    private func initialize() {
        ensureDirectoryExists()
        loadTagCache()
    }
    
    static var defaultBasePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/LocalWhisper/knowledge")
    }
    
    /// Update the base path
    func updateBasePath(_ newPath: URL) {
        self.baseURL = newPath
        ensureDirectoryExists()
    }
    
    // MARK: - Auto Refresh
    
    /// Start automatic refresh timer
    func startAutoRefresh(intervalMinutes: Int) {
        stopAutoRefresh()
        
        logger.info("Starting KB auto-refresh (every \(intervalMinutes) min)")
        
        refreshTask = Task {
            // Initial delay to let models load
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000) // 30 seconds
            
            while !Task.isCancelled {
                do {
                    try await rebuild()
                } catch {
                    logger.error("KB auto-rebuild failed: \(error.localizedDescription)")
                    lastError = error.localizedDescription
                }
                
                // Wait for next refresh interval
                let nanoseconds = UInt64(intervalMinutes) * 60 * 1_000_000_000
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
    }
    
    /// Stop automatic refresh
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
    
    // MARK: - Rebuild
    
    /// Rebuild the entire knowledge base
    func rebuild() async throws {
        guard await tagService.isModelLoaded else {
            logger.warning("Tag model not loaded, skipping KB rebuild")
            throw KnowledgeBaseError.tagModelNotLoaded
        }
        
        guard !isRebuilding else {
            logger.warning("KB rebuild already in progress")
            return
        }
        
        isRebuilding = true
        lastError = nil
        
        logger.info("Rebuilding knowledge base...")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        defer {
            isRebuilding = false
        }
        
        do {
            // 1. Read all ledger entries
            let entries = try await ledgerService.getAllEntries()
            
            guard !entries.isEmpty else {
                logger.info("No ledger entries found, skipping rebuild")
                return
            }
            
            // 2. Extract tags for entries that aren't cached
            var allTags: [String: [LedgerEntry]] = [:]
            var processedCount = 0
            
            for entry in entries {
                let tags: [String]
                
                if let cached = tagCache[entry.id] {
                    tags = cached
                } else {
                    // Extract tags using LLM
                    do {
                        tags = try await tagService.extractTags(from: entry.text, appContext: entry.appContext)
                        tagCache[entry.id] = tags
                        processedCount += 1
                    } catch {
                        logger.warning("Failed to extract tags for entry: \(error.localizedDescription)")
                        continue
                    }
                }
                
                // Group entries by tag
                for tag in tags {
                    allTags[tag, default: []].append(entry)
                }
            }
            
            // Save tag cache if we processed new entries
            if processedCount > 0 {
                saveTagCache()
            }
            
            // 3. Generate knowledge base files
            try await generateIndex(entries: entries, allTags: allTags)
            try await generateTagFiles(allTags: allTags)
            try await generateWeeklySummaries(entries: entries)
            
            lastRefresh = Date()
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            logger.info("KB rebuilt in \(String(format: "%.2f", elapsed))s - \(entries.count) entries, \(allTags.count) tags, \(processedCount) newly processed")
            
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - File Generation
    
    private func generateIndex(entries: [LedgerEntry], allTags: [String: [LedgerEntry]]) async throws {
        let sortedTags = allTags.sorted { $0.value.count > $1.value.count }
        let topTags = sortedTags.prefix(15)
        
        // Get this week's entries
        let calendar = Calendar(identifier: .iso8601)
        let thisWeek = calendar.component(.weekOfYear, from: Date())
        let thisYear = calendar.component(.yearForWeekOfYear, from: Date())
        let thisWeekId = "\(thisYear)-W\(String(format: "%02d", thisWeek))"
        let thisWeekCount = entries.filter { $0.weekIdentifier == thisWeekId }.count
        
        // Get all weeks for summary list
        let weeks = Set(entries.map { $0.weekIdentifier }).sorted().reversed()
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        
        let content = """
        # Knowledge Base

        > Auto-generated from your voice transcriptions.
        > Last updated: \(dateFormatter.string(from: Date()))

        ## Stats

        | Metric | Value |
        |--------|-------|
        | Total entries | \(entries.count) |
        | This week | \(thisWeekCount) |
        | Total tags | \(allTags.count) |

        ## Top Tags

        \(topTags.map { "- [[tags/\($0.key)]] (\($0.value.count) entries)" }.joined(separator: "\n"))

        ## Weekly Summaries

        \(weeks.prefix(12).map { "- [[weekly/\($0)]]" }.joined(separator: "\n"))

        ---

        *This knowledge base is automatically built from your transcription ledger.*
        """
        
        try content.write(to: baseURL.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
    }
    
    private func generateTagFiles(allTags: [String: [LedgerEntry]]) async throws {
        let tagsDir = baseURL.appendingPathComponent("tags")
        
        // Clear existing tag files
        try? FileManager.default.removeItem(at: tagsDir)
        try FileManager.default.createDirectory(at: tagsDir, withIntermediateDirectories: true)
        
        for (tag, entries) in allTags.sorted(by: { $0.key < $1.key }) {
            // Sort entries by date (newest first)
            let sortedEntries = entries.sorted { $0.timestamp > $1.timestamp }
            
            let entriesContent = sortedEntries.map { entry in
                """
                ### \(entry.formattedDateTime) | \(entry.appContext)
                
                \(entry.text)
                
                → [[../../ledger/\(entry.weekIdentifier)]]
                """
            }.joined(separator: "\n\n---\n\n")
            
            let content = """
            # #\(tag)

            **\(entries.count) entries**

            ---

            \(entriesContent)

            ---

            [[../index|← Back to Index]]
            """
            
            // Sanitize tag for filename
            let safeTag = tag
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: "\\", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            
            try content.write(
                to: tagsDir.appendingPathComponent("\(safeTag).md"),
                atomically: true,
                encoding: .utf8
            )
        }
    }
    
    private func generateWeeklySummaries(entries: [LedgerEntry]) async throws {
        let weeklyDir = baseURL.appendingPathComponent("weekly")
        
        // Clear existing weekly files
        try? FileManager.default.removeItem(at: weeklyDir)
        try FileManager.default.createDirectory(at: weeklyDir, withIntermediateDirectories: true)
        
        // Group entries by week
        let byWeek = Dictionary(grouping: entries) { $0.weekIdentifier }
        
        for (week, weekEntries) in byWeek.sorted(by: { $0.key > $1.key }) {
            // Collect tags for this week
            var weekTags: [String: Int] = [:]
            for entry in weekEntries {
                if let tags = tagCache[entry.id] {
                    for tag in tags {
                        weekTags[tag, default: 0] += 1
                    }
                }
            }
            
            // Count apps
            let appCounts = Dictionary(grouping: weekEntries) { $0.appContext }
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }
            
            let topApps = appCounts.prefix(5)
                .map { "\($0.key) (\($0.value))" }
                .joined(separator: ", ")
            
            let topTagsStr = weekTags
                .sorted { $0.value > $1.value }
                .prefix(10)
                .map { "[[../tags/\($0.key)|#\($0.key)]] (\($0.value))" }
                .joined(separator: ", ")
            
            // Sort entries by time (oldest first for reading)
            let sortedEntries = weekEntries.sorted { $0.timestamp < $1.timestamp }
            
            // Group by day
            let byDay = Dictionary(grouping: sortedEntries) { $0.dayOfWeek }
            let dayOrder = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
            
            var daysContent = ""
            for day in dayOrder {
                let dayKey = byDay.keys.first { $0.contains(day) }
                if let key = dayKey, let dayEntries = byDay[key] {
                    daysContent += "\n### \(key)\n\n"
                    for entry in dayEntries {
                        daysContent += "- **\(entry.timeString)** (\(entry.appContext)): \(entry.text)\n"
                    }
                }
            }
            
            let content = """
            # \(formatWeekTitle(week))

            **\(weekEntries.count) entries** | Top contexts: \(topApps)

            ## Tags

            \(topTagsStr.isEmpty ? "_No tags extracted yet_" : topTagsStr)

            ## Entries by Day
            \(daysContent)

            ---

            [[../index|← Back to Index]] | [[../../ledger/\(week)|View Raw Ledger]]
            """
            
            try content.write(
                to: weeklyDir.appendingPathComponent("\(week).md"),
                atomically: true,
                encoding: .utf8
            )
        }
    }
    
    // MARK: - Tag Cache Persistence
    
    private func loadTagCache() {
        guard FileManager.default.fileExists(atPath: tagCacheURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: tagCacheURL)
            let decoded = try JSONDecoder().decode([String: [String]].self, from: data)
            // Convert string keys back to UUIDs
            tagCache = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, value)
            })
            logger.info("Loaded tag cache with \(self.tagCache.count) entries")
        } catch {
            logger.warning("Failed to load tag cache: \(error.localizedDescription)")
        }
    }
    
    private func saveTagCache() {
        do {
            // Convert UUID keys to strings for JSON
            let encodable = Dictionary(uniqueKeysWithValues: tagCache.map { ($0.key.uuidString, $0.value) })
            let data = try JSONEncoder().encode(encodable)
            try data.write(to: tagCacheURL)
            logger.info("Saved tag cache with \(self.tagCache.count) entries")
        } catch {
            logger.warning("Failed to save tag cache: \(error.localizedDescription)")
        }
    }
    
    /// Clear the tag cache (forces re-extraction on next rebuild)
    func clearTagCache() {
        tagCache.removeAll()
        try? FileManager.default.removeItem(at: tagCacheURL)
        logger.info("Tag cache cleared")
    }
    
    // MARK: - Helpers
    
    private func formatWeekTitle(_ week: String) -> String {
        // Convert "2026-W05" to "Week 5, 2026"
        let components = week.split(separator: "-")
        guard components.count == 2,
              let year = components.first,
              let weekPart = components.last,
              weekPart.hasPrefix("W"),
              let weekNum = Int(weekPart.dropFirst()) else {
            return week
        }
        return "Week \(weekNum), \(year)"
    }
    
    private func ensureDirectoryExists() {
        let dirs = [
            baseURL,
            baseURL.appendingPathComponent("tags"),
            baseURL.appendingPathComponent("weekly")
        ]
        
        for dir in dirs {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        logger.info("Knowledge base directory ready: \(self.baseURL.path)")
    }
}

// MARK: - Errors

enum KnowledgeBaseError: LocalizedError {
    case tagModelNotLoaded
    case rebuildFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .tagModelNotLoaded:
            return "Tag extraction model is not loaded"
        case .rebuildFailed(let message):
            return "Knowledge base rebuild failed: \(message)"
        }
    }
}
