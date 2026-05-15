import Foundation

/// A long-form note produced by the Plaud-style flow: long recording →
/// transcription → LLM summarization into structured markdown.
struct Note: Codable, Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    /// User-editable title. Auto-extracted from the LLM output's first heading,
    /// or falls back to a timestamp-based title.
    var title: String
    /// Full markdown produced by the LLM (Summary / Key Points / Action Items …).
    var markdown: String
    /// The original Whisper transcription (verbatim), kept so the user can
    /// re-summarize with a different prompt or model.
    let rawTranscription: String
    let durationSeconds: Double
    let detectedLanguages: [String]
    let whisperModel: String
    let llmModel: String?
    let processingMsTranscription: Int
    let processingMsLLM: Int
    /// True if the LLM step failed or was skipped — markdown then contains the raw transcription.
    let llmSucceeded: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        title: String,
        markdown: String,
        rawTranscription: String,
        durationSeconds: Double,
        detectedLanguages: [String],
        whisperModel: String,
        llmModel: String?,
        processingMsTranscription: Int,
        processingMsLLM: Int,
        llmSucceeded: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.markdown = markdown
        self.rawTranscription = rawTranscription
        self.durationSeconds = durationSeconds
        self.detectedLanguages = detectedLanguages
        self.whisperModel = whisperModel
        self.llmModel = llmModel
        self.processingMsTranscription = processingMsTranscription
        self.processingMsLLM = processingMsLLM
        self.llmSucceeded = llmSucceeded
    }

    /// Heuristic: pull a title from the markdown's first `#` heading.
    static func extractTitle(fromMarkdown md: String, fallback: String) -> String {
        for line in md.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            if trimmed.hasPrefix("## ") {
                return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }
        }
        return fallback
    }
}
