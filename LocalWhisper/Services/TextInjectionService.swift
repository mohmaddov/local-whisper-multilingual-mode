import Foundation
import AppKit
import Carbon.HIToolbox
import os.log

private let injectionLogger = Logger(subsystem: "com.localwispr.app", category: "TextInjection")

/// Injects transcribed text into the currently focused application
actor TextInjectionService {
    
    /// Character to keycode mapping for US keyboard layout.
    /// Maps each character to (virtual keycode, needsShift modifier).
    private let charToKeyCode: [Character: (keyCode: UInt16, shift: Bool)] = [
        // Letters
        "a": (0, false),  "A": (0, true),
        "b": (11, false), "B": (11, true),
        "c": (8, false),  "C": (8, true),
        "d": (2, false),  "D": (2, true),
        "e": (14, false), "E": (14, true),
        "f": (3, false),  "F": (3, true),
        "g": (5, false),  "G": (5, true),
        "h": (4, false),  "H": (4, true),
        "i": (34, false), "I": (34, true),
        "j": (38, false), "J": (38, true),
        "k": (40, false), "K": (40, true),
        "l": (37, false), "L": (37, true),
        "m": (46, false), "M": (46, true),
        "n": (45, false), "N": (45, true),
        "o": (31, false), "O": (31, true),
        "p": (35, false), "P": (35, true),
        "q": (12, false), "Q": (12, true),
        "r": (15, false), "R": (15, true),
        "s": (1, false),  "S": (1, true),
        "t": (17, false), "T": (17, true),
        "u": (32, false), "U": (32, true),
        "v": (9, false),  "V": (9, true),
        "w": (13, false), "W": (13, true),
        "x": (7, false),  "X": (7, true),
        "y": (16, false), "Y": (16, true),
        "z": (6, false),  "Z": (6, true),
        // Numbers (shifted handled on same key)
        "0": (29, false), "1": (18, false), "2": (19, false),
        "3": (20, false), "4": (21, false), "5": (23, false),
        "6": (22, false), "7": (26, false), "8": (28, false),
        "9": (25, false),
        // Shifted numbers
        "!": (18, true),  "@": (19, true),  "#": (20, true),
        "$": (21, true),  "%": (23, true),  "^": (22, true),
        "&": (26, true),  "*": (28, true),  "(": (25, true),
        ")": (29, true),
        // Whitespace
        " ": (49, false),
        "\n": (36, false),  // Return
        "\t": (48, false),  // Tab
        // Punctuation
        "-": (27, false), "_": (27, true),
        "=": (24, false), "+": (24, true),
        "[": (33, false), "{": (33, true),
        "]": (30, false), "}": (30, true),
        "\\": (42, false), "|": (42, true),
        ";": (41, false), ":": (41, true),
        "'": (39, false), "\"": (39, true),
        ",": (43, false), "<": (43, true),
        ".": (47, false), ">": (47, true),
        "/": (44, false), "?": (44, true),
        "`": (50, false), "~": (50, true),
    ]
    
    /// Inject text - copies to clipboard and auto-pastes, or simulates keypresses
    func injectText(_ text: String, useClipboardFallback: Bool = true, useSimulateKeypresses: Bool = false) async throws {
        injectionLogger.info("Injecting text (\(useSimulateKeypresses ? "keypresses" : "paste")): \(text.prefix(50))...")
        
        if useSimulateKeypresses {
            simulateKeypresses(text)
        } else {
            // Step 1: Copy to clipboard
            copyToClipboard(text)
            injectionLogger.info("Text copied to clipboard")
            
            // Step 2: Small delay to ensure clipboard is ready
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            // Step 3: Simulate Cmd+V to paste
            simulatePaste()
            injectionLogger.info("Paste command sent")
        }
    }
    
    /// Copy text to clipboard
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    /// Simulate Cmd+V keypress using CGEvent
    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // V key = keycode 9
        let vKeyCode: CGKeyCode = 9
        
        // Create key down event
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            injectionLogger.error("Failed to create keyDown event")
            return
        }
        
        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            injectionLogger.error("Failed to create keyUp event")
            return
        }
        
        // Set Command modifier for both events
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        // Post events to HID tap (works with accessibility permission)
        keyDown.post(tap: .cghidEventTap)
        usleep(5000) // 5ms delay between key down and up
        keyUp.post(tap: .cghidEventTap)
        
        injectionLogger.info("Cmd+V keystroke posted")
    }
    
    /// Simulate typing each character individually via CGEvent keypresses.
    /// This mode works with apps that don't handle Cmd+V properly (e.g., Emacs, terminals).
    private func simulateKeypresses(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        for char in text {
            guard let (keyCode, needsShift) = charToKeyCode[char] else {
                injectionLogger.warning("Unsupported character for keypress simulation: \(char)")
                // Skip characters we don't have a mapping for
                continue
            }
            
            // Create key down event
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else {
                injectionLogger.error("Failed to create keyDown for char: \(char)")
                continue
            }
            
            // Create key up event
            guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
                injectionLogger.error("Failed to create keyUp for char: \(char)")
                continue
            }
            
            // Apply Shift modifier if needed
            if needsShift {
                keyDown.flags = .maskShift
                keyUp.flags = .maskShift
            }
            
            // Post events to HID tap
            keyDown.post(tap: .cghidEventTap)
            usleep(2000) // 2ms between key down and up
            keyUp.post(tap: .cghidEventTap)
            usleep(2000) // 2ms between characters
        }
        
        injectionLogger.info("Simulated \(text.count) keypresses")
    }
}

// MARK: - Errors
enum TextInjectionError: LocalizedError {
    case injectionFailed
    case accessibilityNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .injectionFailed:
            return "Failed to inject text into the focused application"
        case .accessibilityNotAvailable:
            return "Accessibility permission is required for text injection"
        }
    }
}
