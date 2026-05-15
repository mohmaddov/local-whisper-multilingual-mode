import SwiftUI
import Combine

/// Global application state container
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
    // MARK: - Published State
    @Published var transcriptionState: TranscriptionState = .idle
    /// Independent state machine for the note-taking flow (Plaud-style: tap to
    /// start, tap to stop, then transcribe + summarize). Kept separate from
    /// `transcriptionState` which drives the push-to-talk dictation flow.
    @Published var noteState: NoteRecordingState = .idle
    @Published var noteElapsedSeconds: TimeInterval = 0
    @Published var noteRecordingStartedAt: Date? = nil
    @Published var lastTranscription: String = ""
    @Published var errorMessage: String?
    @Published var modelLoadProgress: Double = 0.0
    @Published var isModelLoaded: Bool = false
    /// Rolling buffer of recent peak audio levels (0...1) for the recording overlay waveform.
    @Published var recentAudioLevels: [Float] = []
    /// Identifier of the model currently being downloaded/loaded in the background.
    /// `nil` when no download is in progress. The active model (if any) remains
    /// usable while this is non-nil.
    @Published var downloadingModel: String? = nil
    /// Identifier of the currently active (loaded) model, as reported by the
    /// transcription service. May differ from `selectedModel` while a download
    /// is in flight.
    @Published var activeModelName: String? = nil
    
    // MARK: - Settings (stored in UserDefaults)
    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "selectedModel") }
    }
    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    @Published var useClipboardFallback: Bool {
        didSet { UserDefaults.standard.set(useClipboardFallback, forKey: "useClipboardFallback") }
    }
    @Published var useSimulateKeypresses: Bool {
        didSet { UserDefaults.standard.set(useSimulateKeypresses, forKey: "useSimulateKeypresses") }
    }
    @Published var customVocabulary: [String] {
        didSet { UserDefaults.standard.set(customVocabulary, forKey: "customVocabulary") }
    }
    @Published var muteAudioWhileRecording: Bool {
        didSet { UserDefaults.standard.set(muteAudioWhileRecording, forKey: "muteAudioWhileRecording") }
    }
    @Published var multilingualMode: Bool {
        didSet { UserDefaults.standard.set(multilingualMode, forKey: "multilingualMode") }
    }
    @Published var dictationCommandsEnabled: Bool {
        didSet { UserDefaults.standard.set(dictationCommandsEnabled, forKey: "dictationCommandsEnabled") }
    }
    /// Stored as a JSON array of {"trigger": "...", "replacement": "..."} dicts in UserDefaults.
    @Published var dictationCommands: [DictationCommand] {
        didSet {
            if let data = try? JSONEncoder().encode(dictationCommands) {
                UserDefaults.standard.set(data, forKey: "dictationCommands")
            }
        }
    }
    
    // MARK: - Proxy Settings
    @Published var proxyEnabled: Bool {
        didSet { 
            UserDefaults.standard.set(proxyEnabled, forKey: "proxyEnabled")
            applyProxySettings()
        }
    }
    @Published var proxyHost: String {
        didSet { 
            UserDefaults.standard.set(proxyHost, forKey: "proxyHost")
            applyProxySettings()
        }
    }
    @Published var proxyPort: String {
        didSet { 
            UserDefaults.standard.set(proxyPort, forKey: "proxyPort")
            applyProxySettings()
        }
    }
    @Published var proxyType: ProxyType {
        didSet { 
            UserDefaults.standard.set(proxyType.rawValue, forKey: "proxyType")
            applyProxySettings()
        }
    }
    
    enum ProxyType: String, CaseIterable {
        case http = "HTTP"
        case https = "HTTPS"
        case socks5 = "SOCKS5"
    }
    
    /// Apply proxy settings to environment variables
    func applyProxySettings() {
        if proxyEnabled && !proxyHost.isEmpty && !proxyPort.isEmpty {
            let proxyURL: String
            switch proxyType {
            case .http:
                proxyURL = "http://\(proxyHost):\(proxyPort)"
                setenv("HTTP_PROXY", proxyURL, 1)
                setenv("http_proxy", proxyURL, 1)
            case .https:
                proxyURL = "http://\(proxyHost):\(proxyPort)"
                setenv("HTTPS_PROXY", proxyURL, 1)
                setenv("https_proxy", proxyURL, 1)
                setenv("HTTP_PROXY", proxyURL, 1)
                setenv("http_proxy", proxyURL, 1)
            case .socks5:
                proxyURL = "socks5://\(proxyHost):\(proxyPort)"
                setenv("ALL_PROXY", proxyURL, 1)
                setenv("all_proxy", proxyURL, 1)
            }
            print("[AppState] Proxy configured: \(proxyType.rawValue) \(proxyHost):\(proxyPort)")
        } else {
            // Clear proxy environment variables
            unsetenv("HTTP_PROXY")
            unsetenv("http_proxy")
            unsetenv("HTTPS_PROXY")
            unsetenv("https_proxy")
            unsetenv("ALL_PROXY")
            unsetenv("all_proxy")
            print("[AppState] Proxy disabled")
        }
    }
    
    /// Returns custom vocabulary as a prompt string for the transcription model
    var vocabularyPrompt: String? {
        guard !customVocabulary.isEmpty else { return nil }
        return customVocabulary.joined(separator: ", ")
    }
    
    // MARK: - Services
    let permissionsService: PermissionsService
    let audioService: AudioCaptureService
    let transcriptionService: TranscriptionService
    let textInjectionService: TextInjectionService
    let audioMuteService: AudioMuteService
    let ledgerService: LedgerService
    let errorLogService: ErrorLogService
    let transcriptionLogService: TranscriptionLogService
    let noteService: NoteService
    let tagExtractionService: TagExtractionService
    let noteSummarizationService: NoteSummarizationService
    let coordinator: TranscriptionCoordinator
    
    private init() {
        // Load settings from UserDefaults
        self.selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "openai_whisper-medium"
        self.language = UserDefaults.standard.string(forKey: "language") ?? "en"
        self.useClipboardFallback = UserDefaults.standard.object(forKey: "useClipboardFallback") as? Bool ?? true
        self.useSimulateKeypresses = UserDefaults.standard.object(forKey: "useSimulateKeypresses") as? Bool ?? false
        self.customVocabulary = UserDefaults.standard.stringArray(forKey: "customVocabulary") ?? []
        self.muteAudioWhileRecording = UserDefaults.standard.object(forKey: "muteAudioWhileRecording") as? Bool ?? true
        self.multilingualMode = UserDefaults.standard.object(forKey: "multilingualMode") as? Bool ?? false
        self.dictationCommandsEnabled = UserDefaults.standard.object(forKey: "dictationCommandsEnabled") as? Bool ?? false
        if let data = UserDefaults.standard.data(forKey: "dictationCommands"),
           let decoded = try? JSONDecoder().decode([DictationCommand].self, from: data) {
            self.dictationCommands = decoded
        } else {
            self.dictationCommands = DictationCommand.defaults
        }
        
        // Load proxy settings
        self.proxyEnabled = UserDefaults.standard.bool(forKey: "proxyEnabled")
        self.proxyHost = UserDefaults.standard.string(forKey: "proxyHost") ?? "127.0.0.1"
        self.proxyPort = UserDefaults.standard.string(forKey: "proxyPort") ?? "1087"
        if let proxyTypeRaw = UserDefaults.standard.string(forKey: "proxyType"),
           let type = ProxyType(rawValue: proxyTypeRaw) {
            self.proxyType = type
        } else {
            self.proxyType = .http
        }
        
        self.permissionsService = PermissionsService()
        self.audioService = AudioCaptureService()
        self.transcriptionService = TranscriptionService()
        self.textInjectionService = TextInjectionService()
        self.audioMuteService = AudioMuteService()
        self.ledgerService = LedgerService()
        self.errorLogService = ErrorLogService.shared
        self.transcriptionLogService = TranscriptionLogService()
        self.noteService = NoteService()
        let tagSvc = TagExtractionService()
        self.tagExtractionService = tagSvc
        self.noteSummarizationService = NoteSummarizationService(llm: tagSvc)
        self.coordinator = TranscriptionCoordinator()

        // Inject dependencies after init
        coordinator.configure(
            appState: self,
            audioService: audioService,
            transcriptionService: transcriptionService,
            textInjectionService: textInjectionService,
            audioMuteService: audioMuteService,
            ledgerService: ledgerService,
            errorLogService: errorLogService,
            transcriptionLogService: transcriptionLogService
        )
        
        // Observe transcription service state
        Task {
            for await progress in transcriptionService.loadProgressStream {
                self.modelLoadProgress = progress
            }
        }

        // Observe mic levels for the recording overlay waveform.
        let levelStream = audioService.levelStream
        Task { [weak self] in
            for await level in levelStream {
                guard let self else { return }
                var buf = self.recentAudioLevels
                buf.append(level)
                if buf.count > 96 { buf.removeFirst(buf.count - 96) }
                self.recentAudioLevels = buf
            }
        }
        
        // Apply proxy settings on startup
        applyProxySettings()
    }
}
