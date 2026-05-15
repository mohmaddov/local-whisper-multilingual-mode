import Foundation
import os.log

private let logger = Logger(subsystem: "com.localwhisper.app", category: "TranscriptionLog")

/// Append-only JSON Lines log of every transcription with full metadata.
/// File: ~/Documents/LocalWhisper/transcriptions.jsonl (one JSON object per line).
actor TranscriptionLogService {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    static var folderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/LocalWhisper")
    }

    static var fileURL: URL {
        folderURL.appendingPathComponent("transcriptions.jsonl")
    }

    init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try? fileManager.createDirectory(at: Self.folderURL, withIntermediateDirectories: true)
    }

    /// Append a record to the log. Single line of JSON terminated by \n.
    func append(_ record: TranscriptionRecord) {
        do {
            let data = try encoder.encode(record)
            guard var line = String(data: data, encoding: .utf8) else { return }
            line = line.replacingOccurrences(of: "\n", with: " ") + "\n"
            guard let lineData = line.data(using: .utf8) else { return }

            let url = Self.fileURL
            if fileManager.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    handle.seekToEndOfFile()
                    handle.write(lineData)
                }
            } else {
                try lineData.write(to: url)
            }
        } catch {
            logger.error("Failed to encode/append record: \(error.localizedDescription)")
        }
    }

    /// Read all records. Tolerates corrupted lines (skipped + logged).
    func readAll() -> [TranscriptionRecord] {
        guard let content = try? String(contentsOf: Self.fileURL, encoding: .utf8) else {
            return []
        }
        var records: [TranscriptionRecord] = []
        for (idx, raw) in content.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            let line = String(raw)
            guard let data = line.data(using: .utf8) else { continue }
            do {
                let record = try decoder.decode(TranscriptionRecord.self, from: data)
                records.append(record)
            } catch {
                logger.warning("Skipping corrupted JSONL line \(idx): \(error.localizedDescription)")
            }
        }
        return records.sorted { $0.timestamp > $1.timestamp }
    }

    /// Delete a specific record by id (rewrites the file).
    func delete(id: UUID) {
        let remaining = readAll().filter { $0.id != id }
        rewrite(remaining)
    }

    /// Clear all records.
    func clear() {
        try? "".write(to: Self.fileURL, atomically: true, encoding: .utf8)
    }

    private func rewrite(_ records: [TranscriptionRecord]) {
        let sorted = records.sorted { $0.timestamp < $1.timestamp }
        var output = ""
        for r in sorted {
            if let data = try? encoder.encode(r),
               let line = String(data: data, encoding: .utf8) {
                output += line.replacingOccurrences(of: "\n", with: " ") + "\n"
            }
        }
        try? output.write(to: Self.fileURL, atomically: true, encoding: .utf8)
    }

    /// Export all records as plain text (one entry per block).
    func exportAsText() -> String {
        let records = readAll().sorted { $0.timestamp < $1.timestamp }
        var out = ""
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .medium
        for r in records {
            out += "[\(df.string(from: r.timestamp))] \(r.appContext) · \(Int(r.durationSeconds))s · "
            out += r.detectedLanguages.map { TranscriptionRecord.languageDisplayName($0) }.joined(separator: "/")
            out += "\n\(r.text)\n\n"
        }
        return out
    }

    /// Export a single record as SubRip (.srt) subtitles. Uses per-segment
    /// timestamps when available, falling back to a single cue for the whole text.
    nonisolated static func exportAsSRT(_ record: TranscriptionRecord) -> String {
        let cues = subtitleCues(for: record)
        var out = ""
        for (idx, cue) in cues.enumerated() {
            out += "\(idx + 1)\n"
            out += "\(srtTimestamp(cue.start)) --> \(srtTimestamp(cue.end))\n"
            out += "\(cue.text)\n\n"
        }
        return out
    }

    /// Export a single record as WebVTT (.vtt) subtitles.
    nonisolated static func exportAsVTT(_ record: TranscriptionRecord) -> String {
        let cues = subtitleCues(for: record)
        var out = "WEBVTT\n\n"
        for cue in cues {
            out += "\(vttTimestamp(cue.start)) --> \(vttTimestamp(cue.end))\n"
            out += "\(cue.text)\n\n"
        }
        return out
    }

    private struct Cue { let start: Double; let end: Double; let text: String }

    nonisolated private static func subtitleCues(for record: TranscriptionRecord) -> [Cue] {
        let timed = record.segments.compactMap { seg -> Cue? in
            guard let s = seg.startSeconds, let e = seg.endSeconds, e > s,
                  !seg.text.isEmpty else { return nil }
            return Cue(start: s, end: e, text: seg.text)
        }
        if !timed.isEmpty { return timed }
        // Fallback: single cue spanning the whole recording.
        return [Cue(start: 0, end: record.durationSeconds, text: record.text)]
    }

    nonisolated private static func srtTimestamp(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds - floor(seconds)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    nonisolated private static func vttTimestamp(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds - floor(seconds)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}
