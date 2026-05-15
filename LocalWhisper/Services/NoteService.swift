import Foundation
import os.log

private let logger = Logger(subsystem: "com.localwhisper.app", category: "NoteService")

/// Append-only JSONL storage for AI-generated notes.
/// File: ~/Documents/LocalWhisper/notes.jsonl
actor NoteService {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    static var folderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/LocalWhisper")
    }

    static var fileURL: URL {
        folderURL.appendingPathComponent("notes.jsonl")
    }

    init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try? fileManager.createDirectory(at: Self.folderURL, withIntermediateDirectories: true)
    }

    func append(_ note: Note) {
        do {
            let data = try encoder.encode(note)
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
            logger.error("Failed to encode/append note: \(error.localizedDescription)")
        }
    }

    func readAll() -> [Note] {
        guard let content = try? String(contentsOf: Self.fileURL, encoding: .utf8) else {
            return []
        }
        var notes: [Note] = []
        for raw in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            guard let data = line.data(using: .utf8) else { continue }
            if let note = try? decoder.decode(Note.self, from: data) {
                notes.append(note)
            }
        }
        return notes.sorted { $0.timestamp > $1.timestamp }
    }

    func delete(id: UUID) {
        let remaining = readAll().filter { $0.id != id }
        rewrite(remaining)
    }

    func update(_ note: Note) {
        var all = readAll()
        if let idx = all.firstIndex(where: { $0.id == note.id }) {
            all[idx] = note
            rewrite(all)
        }
    }

    private func rewrite(_ notes: [Note]) {
        let sorted = notes.sorted { $0.timestamp < $1.timestamp }
        var output = ""
        for n in sorted {
            if let data = try? encoder.encode(n),
               let line = String(data: data, encoding: .utf8) {
                output += line.replacingOccurrences(of: "\n", with: " ") + "\n"
            }
        }
        try? output.write(to: Self.fileURL, atomically: true, encoding: .utf8)
    }
}
