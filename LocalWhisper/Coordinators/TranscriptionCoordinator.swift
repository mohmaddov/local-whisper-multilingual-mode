import Foundation
import SwiftUI
import AppKit
import os.log

private let logger = Logger(subsystem: "com.localwispr.app", category: "Coordinator")

/// Orchestrates the hotkey → record → transcribe → inject workflow
@MainActor
final class TranscriptionCoordinator: ObservableObject {
    private weak var appState: AppState?
    private var audioService: AudioCaptureService?
    private var transcriptionService: TranscriptionService?
    private var textInjectionService: TextInjectionService?
    private var audioMuteService: AudioMuteService?
    private var ledgerService: LedgerService?
    private var errorLogService: ErrorLogService?
    private var transcriptionLogService: TranscriptionLogService?

    private var recordingTask: Task<Void, Never>?

    func configure(
        appState: AppState,
        audioService: AudioCaptureService,
        transcriptionService: TranscriptionService,
        textInjectionService: TextInjectionService,
        audioMuteService: AudioMuteService,
        ledgerService: LedgerService,
        errorLogService: ErrorLogService,
        transcriptionLogService: TranscriptionLogService
    ) {
        self.appState = appState
        self.audioService = audioService
        self.transcriptionService = transcriptionService
        self.textInjectionService = textInjectionService
        self.audioMuteService = audioMuteService
        self.ledgerService = ledgerService
        self.errorLogService = errorLogService
        self.transcriptionLogService = transcriptionLogService
    }
    
    /// Called when hotkey is pressed - start recording
    func handleHotkeyPressed() async {
        logger.info("handleHotkeyPressed called")
        
        guard let appState = appState,
              let audioService = audioService else {
            logger.error("appState or audioService is nil")
            return
        }
        
        // Check if model is loaded
        let modelLoaded = await transcriptionService?.isModelLoaded == true
        logger.info("Model loaded: \(modelLoaded)")
        
        guard modelLoaded else {
            appState.errorMessage = "Model not loaded yet. Please wait..."
            logger.warning("Model not loaded, aborting")
            return
        }
        
        // Check permissions
        logger.info("Mic: \(appState.permissionsService.microphoneGranted), Accessibility: \(appState.permissionsService.accessibilityGranted)")
        guard appState.permissionsService.allPermissionsGranted else {
            appState.errorMessage = "Please grant microphone and accessibility permissions"
            return
        }
        
        // If already recording, treat as toggle (stop)
        if appState.transcriptionState == .recording {
            await handleHotkeyReleased()
            return
        }
        
        // Start recording
        do {
            appState.transcriptionState = .recording
            appState.errorMessage = nil
            
            // Mute system audio if enabled (so mic doesn't pick up speaker audio)
            if appState.muteAudioWhileRecording, let audioMuteService = audioMuteService {
                do {
                    try await audioMuteService.muteSystemAudio()
                } catch {
                    // Log but don't fail - muting is optional
                    print("[Coordinator] Failed to mute system audio: \(error)")
                }
            }
            
            try await audioService.startRecording()
            NSSound(named: "Tink")?.play()
            print("[Coordinator] Recording started")
        } catch {
            // Restore audio if we muted it
            if appState.muteAudioWhileRecording, let audioMuteService = audioMuteService {
                try? await audioMuteService.restoreSystemAudio()
            }
            appState.transcriptionState = .error(error.localizedDescription)
            appState.errorMessage = error.localizedDescription
            print("[Coordinator] Failed to start recording: \(error)")
        }
    }
    
    /// Called when hotkey is released - stop recording and transcribe
    func handleHotkeyReleased() async {
        logger.info("handleHotkeyReleased called")
        
        guard let appState = appState,
              let audioService = audioService,
              let transcriptionService = transcriptionService,
              let textInjectionService = textInjectionService else {
            logger.error("Missing dependencies in handleHotkeyReleased")
            return
        }
        
        logger.info("Current state: \(String(describing: appState.transcriptionState))")
        guard appState.transcriptionState == .recording else {
            logger.warning("Not in recording state, skipping")
            return
        }
        
        // Stop recording
        let audioData = await audioService.stopRecording()
        NSSound(named: "Pop")?.play()
        
        // Restore system audio if we muted it
        if appState.muteAudioWhileRecording, let audioMuteService = audioMuteService {
            do {
                try await audioMuteService.restoreSystemAudio()
            } catch {
                print("[Coordinator] Failed to restore system audio: \(error)")
            }
        }
        logger.info("Recording stopped, duration: \(String(format: "%.2f", audioData.duration))s, samples: \(audioData.samples.count)")
        
        // Check if too short
        guard !audioData.isTooShort else {
            appState.transcriptionState = .idle
            appState.errorMessage = "Recording too short"
            return
        }
        
        // Transcribe
        appState.transcriptionState = .transcribing
        
        let appContext = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        let multilingual = appState.multilingualMode
        let requestedLanguage: String? = multilingual ? nil : appState.language

        do {
            let outcome: TranscriptionOutcome
            if multilingual {
                outcome = try await transcriptionService.transcribeMultilingualRich(
                    audioData,
                    prompt: appState.vocabularyPrompt
                )
            } else {
                outcome = try await transcriptionService.transcribeRich(
                    audioData,
                    language: appState.language,
                    prompt: appState.vocabularyPrompt
                )
            }

            logger.info("Transcription [\(outcome.detectedLanguages.joined(separator: ","))] (\(outcome.processingMs)ms): \(outcome.text)")

            // Apply dictation magic words (e.g. "new line" -> \n) before storing & injecting.
            let processedText: String = {
                guard appState.dictationCommandsEnabled else { return outcome.text }
                return DictationCommand.apply(appState.dictationCommands, to: outcome.text)
            }()
            appState.lastTranscription = processedText

            // Persist rich JSONL record
            if let transcriptionLogService = transcriptionLogService {
                let record = TranscriptionRecord(
                    text: outcome.text,
                    appContext: appContext,
                    durationSeconds: audioData.duration,
                    processingMs: outcome.processingMs,
                    mode: multilingual ? .multilingualVAD : .singleLanguage,
                    modelName: outcome.modelName,
                    requestedLanguage: requestedLanguage,
                    detectedLanguages: outcome.detectedLanguages,
                    segments: outcome.segments,
                    errorMessage: nil
                )
                await transcriptionLogService.append(record)
            }

            // Also append to legacy markdown ledger for backward compatibility
            if !outcome.text.isEmpty, let ledgerService = ledgerService {
                let entry = LedgerEntry(text: outcome.text, appContext: appContext, duration: audioData.duration)
                do {
                    try await ledgerService.append(entry)
                } catch {
                    await errorLogService?.log(.warning, "Failed to append ledger entry: \(error.localizedDescription)", source: "Ledger")
                }
            }

            // Inject text (with dictation rewrite applied).
            if !processedText.isEmpty {
                try await textInjectionService.injectText(
                    processedText,
                    useClipboardFallback: appState.useClipboardFallback,
                    useSimulateKeypresses: appState.useSimulateKeypresses
                )
            }

            appState.transcriptionState = .idle
            appState.errorMessage = nil

        } catch {
            appState.transcriptionState = .error(error.localizedDescription)
            appState.errorMessage = error.localizedDescription
            logger.error("Transcription failed: \(error.localizedDescription)")
            await errorLogService?.logError(error, source: "Transcription")
            // Also log the failed attempt to the transcription log so failures are visible
            if let transcriptionLogService = transcriptionLogService {
                let record = TranscriptionRecord(
                    text: "",
                    appContext: appContext,
                    durationSeconds: audioData.duration,
                    processingMs: 0,
                    mode: multilingual ? .multilingualVAD : .singleLanguage,
                    modelName: (await transcriptionService.loadedModelName) ?? "unknown",
                    requestedLanguage: requestedLanguage,
                    detectedLanguages: [],
                    segments: [],
                    errorMessage: error.localizedDescription
                )
                await transcriptionLogService.append(record)
            }
            
            // Reset to idle after showing error
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                if case .error = appState.transcriptionState {
                    appState.transcriptionState = .idle
                }
            }
        }
    }
    
    /// Cancel current operation
    func cancel() async {
        guard let appState = appState,
              let audioService = audioService else { return }
        
        if appState.transcriptionState == .recording {
            _ = await audioService.stopRecording()
            
            // Restore system audio if we muted it
            if appState.muteAudioWhileRecording, let audioMuteService = audioMuteService {
                try? await audioMuteService.restoreSystemAudio()
            }
        }
        
        recordingTask?.cancel()
        appState.transcriptionState = .idle
    }
}
