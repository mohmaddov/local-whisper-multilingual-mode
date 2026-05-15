import Foundation
import os.log

private let logger = Logger(subsystem: "com.localwhisper.app", category: "ErrorLog")

/// Persistent error/bug log written to ~/Library/Logs/LocalWhisper/errors.log
actor ErrorLogService {
    static let shared = ErrorLogService()

    private let fileManager = FileManager.default

    static var logFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LocalWhisper/errors.log")
    }

    static var logFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LocalWhisper")
    }

    enum Severity: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    init() {
        try? fileManager.createDirectory(at: Self.logFolderURL, withIntermediateDirectories: true)
    }

    /// Append a log entry with timestamp + severity + source.
    func log(_ severity: Severity, _ message: String, source: String = "App") {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(severity.rawValue)] [\(source)] \(message)\n"

        switch severity {
        case .info:    logger.info("\(source): \(message, privacy: .public)")
        case .warning: logger.warning("\(source): \(message, privacy: .public)")
        case .error:   logger.error("\(source): \(message, privacy: .public)")
        }

        guard let data = line.data(using: .utf8) else { return }
        let url = Self.logFileURL

        if fileManager.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            }
        } else {
            try? data.write(to: url)
        }
    }

    /// Convenience for catching thrown errors.
    func logError(_ error: Error, source: String = "App") {
        log(.error, "\(error.localizedDescription)", source: source)
    }

    /// Read the last `lineCount` lines (newest last). Empty if file missing.
    func readTail(lineCount: Int = 500) -> String {
        guard let content = try? String(contentsOf: Self.logFileURL, encoding: .utf8) else {
            return ""
        }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let tail = lines.suffix(lineCount)
        return tail.joined(separator: "\n")
    }

    /// Clear the log file.
    func clear() {
        try? "".write(to: Self.logFileURL, atomically: true, encoding: .utf8)
    }
}
