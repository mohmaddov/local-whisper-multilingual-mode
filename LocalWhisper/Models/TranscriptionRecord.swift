import Foundation

/// A single transcription event with full metadata. Persisted as JSON Lines.
struct TranscriptionRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let text: String
    let appContext: String
    let durationSeconds: Double
    let processingMs: Int
    let mode: Mode
    let modelName: String
    let requestedLanguage: String?      // user-selected language ("en", "ru", "" for auto, nil if multilingual)
    let detectedLanguages: [String]     // distinct languages detected across all segments
    let segments: [Segment]
    let errorMessage: String?           // populated only on failure

    enum Mode: String, Codable {
        case singleLanguage
        case multilingualVAD
    }

    struct Segment: Codable, Hashable {
        let language: String?           // language code detected by Whisper for this chunk
        let text: String
        let startSeconds: Double?
        let endSeconds: Double?

        var durationSeconds: Double? {
            guard let s = startSeconds, let e = endSeconds else { return nil }
            return e - s
        }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        text: String,
        appContext: String,
        durationSeconds: Double,
        processingMs: Int,
        mode: Mode,
        modelName: String,
        requestedLanguage: String?,
        detectedLanguages: [String],
        segments: [Segment],
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.appContext = appContext
        self.durationSeconds = durationSeconds
        self.processingMs = processingMs
        self.mode = mode
        self.modelName = modelName
        self.requestedLanguage = requestedLanguage
        self.detectedLanguages = detectedLanguages
        self.segments = segments
        self.errorMessage = errorMessage
    }
}

extension TranscriptionRecord {
    /// Localized display name for a Whisper language code.
    static func languageDisplayName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }

    /// Flag emoji for common Whisper language codes. Falls back to the uppercased code.
    static func languageFlag(_ code: String) -> String {
        let map: [String: String] = [
            "en": "🇬🇧", "fr": "🇫🇷", "ru": "🇷🇺", "es": "🇪🇸", "de": "🇩🇪",
            "it": "🇮🇹", "pt": "🇵🇹", "zh": "🇨🇳", "ja": "🇯🇵", "ko": "🇰🇷",
            "ar": "🇸🇦", "nl": "🇳🇱", "pl": "🇵🇱", "tr": "🇹🇷", "uk": "🇺🇦",
            "sv": "🇸🇪", "da": "🇩🇰", "fi": "🇫🇮", "no": "🇳🇴", "cs": "🇨🇿",
            "el": "🇬🇷", "he": "🇮🇱", "hi": "🇮🇳", "th": "🇹🇭", "vi": "🇻🇳",
            "id": "🇮🇩", "ro": "🇷🇴", "hu": "🇭🇺", "ca": "🇪🇸"
        ]
        return map[code.lowercased()] ?? code.uppercased()
    }
}
