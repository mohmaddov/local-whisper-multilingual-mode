import Foundation
import os.log

private let logger = Logger(subsystem: "com.localwhisper.app", category: "Ledger")

/// Append-only transcription ledger stored as weekly markdown files
actor LedgerService {
    private let baseURL: URL
    private let fileManager = FileManager.default
    
    // Track current day to insert day headers
    private var lastEntryDay: String?
    
    init(basePath: URL? = nil) {
        self.baseURL = basePath ?? Self.defaultBasePath
        // Defer actor-isolated initialization
        Task { await self.initialize() }
    }
    
    private func initialize() {
        ensureDirectoryExists()
    }
    
    static var defaultBasePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/LocalWhisper/ledger")
    }
    
    /// Update the base path (when user changes settings)
    func updateBasePath(_ newPath: URL) {
        // Note: This creates a new instance effectively
        // The actor ensures thread-safe access
    }
    
    // MARK: - Public API
    
    /// Append a new entry to the ledger
    func append(_ entry: LedgerEntry) async throws {
        let filePath = fileURL(for: entry.weekIdentifier)
        let needsDayHeader = lastEntryDay != entry.dayOfWeek
        
        if fileManager.fileExists(atPath: filePath.path) {
            // Append to existing file
            var content = ""
            
            // Add day header if new day
            if needsDayHeader {
                content += "\n## \(entry.dayOfWeek)\n"
            }
            
            content += formatEntry(entry)
            
            let handle = try FileHandle(forWritingTo: filePath)
            handle.seekToEndOfFile()
            if let data = content.data(using: .utf8) {
                handle.write(data)
            }
            try handle.close()
        } else {
            // Create new weekly file with header
            var content = "# Transcription Ledger - \(formatWeekHeader(entry.weekIdentifier))\n\n"
            content += "## \(entry.dayOfWeek)\n"
            content += formatEntry(entry)
            try content.write(to: filePath, atomically: true, encoding: .utf8)
        }
        
        lastEntryDay = entry.dayOfWeek
        logger.info("Appended entry to ledger: \(entry.weekIdentifier) - \(entry.text.prefix(50))...")
    }
    
    /// Read all entries from all ledger files
    func getAllEntries() async throws -> [LedgerEntry] {
        var allEntries: [LedgerEntry] = []
        
        let files = try fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        for file in files {
            let week = file.deletingPathExtension().lastPathComponent
            let entries = try await getEntries(for: week)
            allEntries.append(contentsOf: entries)
        }
        
        return allEntries.sorted { $0.timestamp < $1.timestamp }
    }
    
    /// Read entries for a specific week
    func getEntries(for week: String) async throws -> [LedgerEntry] {
        let filePath = fileURL(for: week)
        
        guard fileManager.fileExists(atPath: filePath.path) else {
            return []
        }
        
        let content = try String(contentsOf: filePath, encoding: .utf8)
        
        // Parse the week identifier to get a base date
        guard let baseDate = parseWeekIdentifier(week) else {
            logger.warning("Could not parse week identifier: \(week)")
            return []
        }
        
        return LedgerEntry.parse(from: content, week: week, date: baseDate)
    }
    
    /// Get list of all week identifiers in the ledger
    func getAllWeeks() async throws -> [String] {
        let files = try fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
        
        return files
    }
    
    /// Get the total entry count without loading all entries
    func getEntryCount() async throws -> Int {
        var count = 0
        
        let files = try fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
        
        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            // Count occurrences of entry headers
            count += content.components(separatedBy: "### ").count - 1
        }
        
        return count
    }
    
    // MARK: - Private Helpers
    
    private func fileURL(for week: String) -> URL {
        baseURL.appendingPathComponent("\(week).md")
    }
    
    private func formatEntry(_ entry: LedgerEntry) -> String {
        """
        
        ### \(entry.timeString)
        - **App**: \(entry.appContext)
        - **Duration**: \(Int(entry.duration))s

        \(entry.text)

        ---
        """
    }
    
    private func formatWeekHeader(_ week: String) -> String {
        // Convert "2026-W05" to "Week 5, 2026"
        let components = week.split(separator: "-")
        guard components.count == 2,
              let year = components.first,
              let weekPart = components.last,
              weekPart.hasPrefix("W") else {
            return week
        }
        
        let weekNum = weekPart.dropFirst() // Remove "W"
        if let num = Int(weekNum) {
            return "Week \(num), \(year)"
        }
        return week
    }
    
    private func parseWeekIdentifier(_ week: String) -> Date? {
        // Parse "2026-W05" format
        let components = week.split(separator: "-")
        guard components.count == 2,
              let year = Int(components[0]),
              components[1].hasPrefix("W"),
              let weekNum = Int(components[1].dropFirst()) else {
            return nil
        }
        
        var dateComponents = DateComponents()
        dateComponents.yearForWeekOfYear = year
        dateComponents.weekOfYear = weekNum
        dateComponents.weekday = 2 // Monday
        
        let calendar = Calendar(identifier: .iso8601)
        return calendar.date(from: dateComponents)
    }
    
    private func ensureDirectoryExists() {
        do {
            try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
            logger.info("Ledger directory ready: \(self.baseURL.path)")
        } catch {
            logger.error("Failed to create ledger directory: \(error.localizedDescription)")
        }
    }
}
