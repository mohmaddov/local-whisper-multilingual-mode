import Foundation

/// Represents a single transcription entry in the ledger
struct LedgerEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let text: String
    let appContext: String      // e.g., "VS Code", "Slack"
    let duration: TimeInterval  // Recording duration in seconds
    
    /// Rough token estimate for LLM context budgeting (~1.3 tokens per word)
    var tokenEstimate: Int {
        let wordCount = text.split(separator: " ").count
        return Int(Double(wordCount) * 1.3)
    }
    
    /// ISO week identifier (e.g., "2026-W05")
    var weekIdentifier: String {
        let calendar = Calendar(identifier: .iso8601)
        let week = calendar.component(.weekOfYear, from: timestamp)
        let year = calendar.component(.yearForWeekOfYear, from: timestamp)
        return "\(year)-W\(String(format: "%02d", week))"
    }
    
    /// Formatted day of week (e.g., "Monday, January 27")
    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: timestamp)
    }
    
    /// Formatted time string (e.g., "14:32:15")
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
    
    /// Formatted date and time for display
    var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        text: String,
        appContext: String,
        duration: TimeInterval
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.appContext = appContext
        self.duration = duration
    }
}

// MARK: - Parsing Support

extension LedgerEntry {
    /// Regex pattern to parse ledger markdown entries
    /// Matches: ### HH:mm:ss followed by metadata and text
    static let entryPattern = #"""
    ###\s+(\d{2}:\d{2}:\d{2})\s*\n
    -\s+\*\*App\*\*:\s+(.+?)\s*\n
    -\s+\*\*Duration\*\*:\s+(\d+)s\s*\n
    \n
    ([\s\S]*?)
    \n---
    """#
    
    /// Parse entries from markdown content for a specific week
    static func parse(from markdown: String, week: String, date: Date) -> [LedgerEntry] {
        var entries: [LedgerEntry] = []
        
        guard let regex = try? NSRegularExpression(pattern: entryPattern, options: [.anchorsMatchLines]) else {
            return entries
        }
        
        let range = NSRange(markdown.startIndex..., in: markdown)
        let matches = regex.matches(in: markdown, options: [], range: range)
        
        let calendar = Calendar(identifier: .iso8601)
        let weekComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        
        for match in matches {
            guard match.numberOfRanges == 5,
                  let timeRange = Range(match.range(at: 1), in: markdown),
                  let appRange = Range(match.range(at: 2), in: markdown),
                  let durationRange = Range(match.range(at: 3), in: markdown),
                  let textRange = Range(match.range(at: 4), in: markdown) else {
                continue
            }
            
            let timeString = String(markdown[timeRange])
            let appContext = String(markdown[appRange])
            let durationString = String(markdown[durationRange])
            let text = String(markdown[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let duration = TimeInterval(durationString) else { continue }
            
            // Parse time and combine with week date
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm:ss"
            guard let time = timeFormatter.date(from: timeString) else { continue }
            
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
            var entryComponents = weekComponents
            entryComponents.hour = timeComponents.hour
            entryComponents.minute = timeComponents.minute
            entryComponents.second = timeComponents.second
            
            guard let entryDate = calendar.date(from: entryComponents) else { continue }
            
            let entry = LedgerEntry(
                timestamp: entryDate,
                text: text,
                appContext: appContext,
                duration: duration
            )
            entries.append(entry)
        }
        
        return entries
    }
}
