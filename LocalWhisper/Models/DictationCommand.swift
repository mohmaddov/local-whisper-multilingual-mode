import Foundation

/// A magic-word rule applied to transcribed text before injection.
/// Example: `trigger = "new line"`, `replacement = "\n"` turns the spoken phrase
/// "new line" into an actual newline character in the injected text.
///
/// Matching is case-insensitive and whole-word (word boundaries enforced via
/// regex). Triggers can be multi-word phrases. Trailing/leading spaces in the
/// surrounding text are collapsed so the result reads naturally.
struct DictationCommand: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var trigger: String
    var replacement: String
    var enabled: Bool = true

    static let defaults: [DictationCommand] = [
        DictationCommand(trigger: "new line", replacement: "\n"),
        DictationCommand(trigger: "new paragraph", replacement: "\n\n"),
        DictationCommand(trigger: "period", replacement: "."),
        DictationCommand(trigger: "comma", replacement: ","),
        DictationCommand(trigger: "question mark", replacement: "?"),
        DictationCommand(trigger: "exclamation mark", replacement: "!"),
        DictationCommand(trigger: "colon", replacement: ":"),
        DictationCommand(trigger: "semicolon", replacement: ";"),
        DictationCommand(trigger: "open parenthesis", replacement: "("),
        DictationCommand(trigger: "close parenthesis", replacement: ")"),
    ]

    /// Apply the given enabled commands to `text`, returning the rewritten string.
    /// Triggers are matched case-insensitively as whole words. Punctuation
    /// replacements consume any adjacent leading whitespace so we don't end up
    /// with "hello , world".
    static func apply(_ commands: [DictationCommand], to text: String) -> String {
        var result = text
        for cmd in commands where cmd.enabled && !cmd.trigger.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: cmd.trigger)
            let isPunctuation = cmd.replacement.count == 1
                && ".,;:!?".contains(cmd.replacement)
            // For punctuation, also eat the space before the trigger.
            let pattern = isPunctuation
                ? "\\s*\\b\(escaped)\\b"
                : "\\b\(escaped)\\b"
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: cmd.replacement)
            )
        }
        return result
    }
}
