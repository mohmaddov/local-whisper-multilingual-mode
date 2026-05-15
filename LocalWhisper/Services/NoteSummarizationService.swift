import Foundation
import os.log

private let logger = Logger(subsystem: "com.localwhisper.app", category: "NoteSummarization")

/// Turns a long transcription into a structured markdown note using the local
/// LLM hosted by `TagExtractionService`. Falls back to the raw transcription
/// if the LLM is unavailable or fails — the recording is never lost.
actor NoteSummarizationService {
    private let llm: TagExtractionService

    init(llm: TagExtractionService) {
        self.llm = llm
    }

    struct Result {
        let markdown: String
        let title: String
        let llmModel: String?
        let processingMs: Int
        let succeeded: Bool
    }

    func summarize(transcription: String, languages: [String]) async -> Result {
        let trimmed = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        let startTime = CFAbsoluteTimeGetCurrent()

        // Skip the LLM step for trivially short text.
        guard trimmed.count >= 40 else {
            return fallback(transcription: trimmed, reason: "transcription too short for summary")
        }

        let loaded = await llm.isModelLoaded
        guard loaded else {
            return fallback(transcription: trimmed, reason: "summarization model not loaded")
        }

        let modelId = await llm.loadedModelId
        let prompt = buildPrompt(transcription: trimmed, languages: languages)
        logger.info("Summarizing transcription (\(trimmed.count) chars) with \(modelId ?? "?", privacy: .public)")

        do {
            let raw = try await llm.generate(prompt: prompt, maxTokens: 700)
            let markdown = cleanResponse(raw)
            let fallbackTitle = "Note " + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
            let title = Note.extractTitle(fromMarkdown: markdown, fallback: fallbackTitle)
            let processingMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            return Result(
                markdown: markdown,
                title: title,
                llmModel: modelId,
                processingMs: processingMs,
                succeeded: true
            )
        } catch {
            logger.error("Summarization failed: \(error.localizedDescription, privacy: .public)")
            return fallback(transcription: trimmed, reason: error.localizedDescription)
        }
    }

    private func fallback(transcription: String, reason: String) -> Result {
        logger.warning("Falling back to raw transcription: \(reason, privacy: .public)")
        let fallbackTitle = "Note " + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        let md = """
        # \(fallbackTitle)

        > AI summary unavailable (\(reason)) — raw transcription below.

        \(transcription)
        """
        return Result(markdown: md, title: fallbackTitle, llmModel: nil, processingMs: 0, succeeded: false)
    }

    private func buildPrompt(transcription: String, languages: [String]) -> String {
        let langHint = languages.isEmpty
            ? "The recording may be in any language."
            : "Detected languages: \(languages.joined(separator: ", "))."
        return """
        You are a meeting/voice-note assistant. Transform the following voice transcription \
        into a structured markdown note. Keep the original language of the transcription.

        \(langHint)

        Use exactly this structure (skip a section if there is nothing relevant):
        # <Short title, max 8 words>
        ## Summary
        2-3 sentence overview.
        ## Key Points
        - bullet points (3-7 items)
        ## Action Items
        - actionable to-dos, if any
        ## Decisions
        - decisions made, if any

        Return ONLY the markdown. Do not wrap it in code fences.

        Transcription:
        \"\"\"
        \(transcription)
        \"\"\"
        """
    }

    /// Strip code fences the LLM may have added despite instructions.
    private func cleanResponse(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove ```markdown ... ``` or ``` ... ``` wrappers.
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if let fenceRange = s.range(of: "```", options: .backwards) {
                s = String(s[..<fenceRange.lowerBound])
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
