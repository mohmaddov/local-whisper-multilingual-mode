import Foundation
@preconcurrency import WhisperKit

/// Handles local transcription using WhisperKit
actor TranscriptionService {
    private var whisperKit: WhisperKit?
    private var isLoading = false
    private var currentModelName: String?
    
    private let progressContinuation: AsyncStream<Double>.Continuation
    let loadProgressStream: AsyncStream<Double>
    
    var isModelLoaded: Bool {
        whisperKit != nil
    }
    
    var loadedModelName: String? {
        currentModelName
    }
    
    init() {
        var continuation: AsyncStream<Double>.Continuation!
        self.loadProgressStream = AsyncStream { continuation = $0 }
        self.progressContinuation = continuation
    }
    
    /// Load the Whisper model
    /// Available models from HuggingFace:
    /// - openai_whisper-medium (~1.5GB, high accuracy)
    /// - distil-whisper_distil-large-v3_turbo (~600MB, fast & accurate)
    /// - openai_whisper-large-v3-v20240930_turbo (~1.6GB, latest checkpoint)
    /// - openai_whisper-large-v3-v20240930 (~3GB, best Whisper accuracy)
    /// - nvidia_parakeet-v3_494MB (~494MB, from argmaxinc/parakeetkit-pro)
    /// - nvidia_parakeet-v3 (~1.3GB, from argmaxinc/parakeetkit-pro)
    func loadModel(modelName: String = "openai_whisper-medium", modelRepo: String? = nil) async {
        guard !isLoading && whisperKit == nil else { 
            print("[TranscriptionService] Skipping load - isLoading: \(isLoading), whisperKit exists: \(whisperKit != nil)")
            return 
        }
        
        isLoading = true
        progressContinuation.yield(0.0)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Log proxy settings for debugging
        logProxySettings()
        
        do {
            progressContinuation.yield(0.1)
            print("[TranscriptionService] ⏳ Loading model: \(modelName)...")
            
            // Initialize WhisperKit with model variant
            // WhisperKit will download from HuggingFace if not cached
            // Use verbose mode to see download progress
            // Note: useBackgroundDownloadSession=false ensures we use the default URLSession
            // which respects system proxy settings
            whisperKit = try await WhisperKit(
                model: modelName,
                modelRepo: modelRepo,
                verbose: true,
                logLevel: .debug,
                prewarm: true,
                load: true,
                download: true,
                useBackgroundDownloadSession: false  // Use foreground session for proxy compatibility
            )
            
            let loadTime = CFAbsoluteTimeGetCurrent() - startTime
            currentModelName = modelName
            
            // Log actual model info from WhisperKit
            if let wk = whisperKit {
                let modelPath = wk.modelFolder?.path ?? "unknown"
                print("[TranscriptionService] 📁 Model folder: \(modelPath)")
                logToFile("[TranscriptionService] 📁 Model folder: \(modelPath)")
            }
            
            progressContinuation.yield(1.0)
            print("[TranscriptionService] ✅ Model \(modelName) loaded successfully in \(String(format: "%.2f", loadTime))s")
            logToFile("[TranscriptionService] ✅ Model \(modelName) loaded successfully in \(String(format: "%.2f", loadTime))s")
        } catch {
            let errorMessage = "[TranscriptionService] ❌ Failed to load model \(modelName): \(error)"
            print(errorMessage)
            logToFile(errorMessage)
            
            // Try with a smaller model as fallback
            if modelName != "openai_whisper-medium" {
                print("[TranscriptionService] 🔄 Retrying with medium model...")
                logToFile("[TranscriptionService] 🔄 Retrying with medium model...")
                isLoading = false
                await loadModel(modelName: "openai_whisper-medium")
                return
            }
            progressContinuation.yield(0.0)
        }
        
        isLoading = false
    }
    
    /// Transcribe audio with per-segment language detection (multilingual mode).
    /// Uses WhisperKit's built-in VAD (voice activity detection) chunking which splits
    /// audio on natural speech pauses, then detects the language independently for each
    /// chunk — enabling seamless switching between languages within a single recording.
    func transcribeMultilingual(_ audio: AudioData, prompt: String? = nil) async throws -> String {
        guard let whisper = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }
        guard !audio.isTooShort else {
            throw TranscriptionError.audioTooShort
        }

        let audioDuration = Double(audio.samples.count) / 16000.0
        print("[TranscriptionService] 🌍 Multilingual transcribing \(String(format: "%.1f", audioDuration))s of audio")
        let startTime = CFAbsoluteTimeGetCurrent()

        var promptTokens: [Int]? = nil
        if let prompt = prompt, !prompt.isEmpty, let tokenizer = whisper.tokenizer {
            let encoded = tokenizer.encode(text: " " + prompt)
            promptTokens = encoded.filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }

        // VAD chunking + per-chunk language detection.
        // WhisperKit automatically detects the language for each chunk when
        // language == nil and detectLanguage == true on a multilingual model.
        let options = DecodingOptions(
            task: .transcribe,
            language: nil,
            usePrefillPrompt: true,
            detectLanguage: true,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            promptTokens: promptTokens,
            chunkingStrategy: .vad
        )

        let results = try await whisper.transcribe(
            audioArray: audio.samples,
            decodeOptions: options
        )

        let transcriptionTime = CFAbsoluteTimeGetCurrent() - startTime
        let speedFactor = audioDuration / transcriptionTime
        print("[TranscriptionService] ⚡ Multilingual transcription completed in \(String(format: "%.2f", transcriptionTime))s (speed factor: \(String(format: "%.1f", speedFactor))x)")

        let rawText = results.compactMap { $0.text }.joined(separator: " ")
        let cleaned = Self.stripWhisperArtifacts(rawText)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove non-speech placeholders Whisper sometimes emits (e.g. "(foreign language)").
    private static func stripWhisperArtifacts(_ text: String) -> String {
        let pattern = #"[\(\[][^\)\]]*?(foreign language|no audio|silence|inaudible|music|background noise|speaking|non-english)[^\(\[]*?[\)\]]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        let cleaned = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        // Collapse multiple spaces
        return cleaned.replacingOccurrences(of: #" +"#, with: " ", options: .regularExpression)
    }

    /// Transcribe audio data to text
    /// - Parameters:
    ///   - audio: The audio data to transcribe
    ///   - language: Language code (e.g., "en", "zh") or empty for auto-detect
    ///   - prompt: Optional initial prompt with custom vocabulary to improve accuracy.
    ///             This is not an LLM-style prompt - it provides examples of spelling and style
    ///             that the model should follow. Works best with larger models.
    func transcribe(_ audio: AudioData, language: String = "en", prompt: String? = nil) async throws -> String {
        guard let whisper = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }
        
        guard !audio.isTooShort else {
            throw TranscriptionError.audioTooShort
        }
        
        let audioDuration = Double(audio.samples.count) / 16000.0  // 16kHz sample rate
        print("[TranscriptionService] 🎤 Transcribing \(String(format: "%.1f", audioDuration))s of audio with model: \(currentModelName ?? "unknown")")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Build prompt tokens from custom vocabulary if provided
        // The prompt tokens guide the model's spelling and style without being an instruction
        var promptTokens: [Int]? = nil
        if let prompt = prompt, !prompt.isEmpty, let tokenizer = whisper.tokenizer {
            // Encode the prompt text and filter out special tokens
            // Special tokens (>= specialTokenBegin) should not be included in the prompt
            let encoded = tokenizer.encode(text: " " + prompt)
            promptTokens = encoded.filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            print("[TranscriptionService] 📝 Custom vocabulary prompt: \"\(prompt)\" (\(promptTokens?.count ?? 0) tokens)")
        }
        
        // Configure decoding options with prompt tokens for custom vocabulary
        let options = DecodingOptions(
            task: .transcribe,
            language: language.isEmpty ? nil : language,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            promptTokens: promptTokens
        )
        
        let results = try await whisper.transcribe(
            audioArray: audio.samples,
            decodeOptions: options
        )
        
        let transcriptionTime = CFAbsoluteTimeGetCurrent() - startTime
        let speedFactor = audioDuration / transcriptionTime
        
        print("[TranscriptionService] ⚡ Transcription completed in \(String(format: "%.2f", transcriptionTime))s (speed factor: \(String(format: "%.1f", speedFactor))x)")
        
        // Combine all segments into final text
        let text = results.compactMap { $0.text }.joined(separator: " ")
        
        // Clean up the text
        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
    
    /// Unload the model to free memory
    func unloadModel() {
        if let modelName = currentModelName {
            print("[TranscriptionService] 🗑️ Unloading model: \(modelName)")
        }
        whisperKit = nil
        currentModelName = nil
    }
    
    /// Log message to file for debugging
    private func logToFile(_ message: String) {
        let logFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LocalWhisper.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }
    
    /// Log system proxy settings for debugging network issues
    private func logProxySettings() {
        // Check environment variables that some tools use
        let envVars = ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "ALL_PROXY", "NO_PROXY"]
        var foundProxy = false
        
        for envVar in envVars {
            if let value = ProcessInfo.processInfo.environment[envVar] {
                print("[TranscriptionService] 🌐 Environment \(envVar): \(value)")
                foundProxy = true
            }
        }
        
        // Check system proxy settings via CFNetwork
        if let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] {
            if let httpProxy = proxySettings["HTTPProxy"] as? String,
               let httpPort = proxySettings["HTTPPort"] as? Int,
               proxySettings["HTTPEnable"] as? Int == 1 {
                print("[TranscriptionService] 🌐 System HTTP Proxy: \(httpProxy):\(httpPort)")
                foundProxy = true
            }
            if let httpsProxy = proxySettings["HTTPSProxy"] as? String,
               let httpsPort = proxySettings["HTTPSPort"] as? Int,
               proxySettings["HTTPSEnable"] as? Int == 1 {
                print("[TranscriptionService] 🌐 System HTTPS Proxy: \(httpsProxy):\(httpsPort)")
                foundProxy = true
            }
            if let pacURL = proxySettings["ProxyAutoConfigURLString"] as? String,
               proxySettings["ProxyAutoConfigEnable"] as? Int == 1 {
                print("[TranscriptionService] 🌐 System PAC URL: \(pacURL)")
                foundProxy = true
            }
        }
        
        if !foundProxy {
            print("[TranscriptionService] 🌐 No proxy configured (direct connection)")
        }
    }
}

// MARK: - Errors
enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case audioTooShort
    case transcriptionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model is not loaded"
        case .audioTooShort:
            return "Audio is too short to transcribe"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        }
    }
}
