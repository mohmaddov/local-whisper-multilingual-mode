import Foundation
import MLXLLM
import MLXLMCommon
import MLXLMHFAPI
import MLXLMTokenizers
import os.log

private let logger = Logger(subsystem: "com.localwhisper.app", category: "TagExtraction")

/// Extracts tags from transcriptions using a local LLM (Qwen via MLX)
actor TagExtractionService {
    private var modelContainer: ModelContainer?
    private var isLoading = false
    private var currentModelId: String?
    
    private let progressContinuation: AsyncStream<Double>.Continuation
    let loadProgressStream: AsyncStream<Double>
    
    var isModelLoaded: Bool { modelContainer != nil }
    var loadedModelId: String? { currentModelId }
    
    // MARK: - Available Models
    
    struct TagModel: Identifiable {
        let id: String
        let name: String
        let size: String
        let description: String
    }
    
    static let availableModels: [TagModel] = [
        TagModel(
            id: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
            name: "Qwen 0.5B",
            size: "~350 MB",
            description: "Fastest, good for basic tagging"
        ),
        TagModel(
            id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            name: "Qwen 1.5B",
            size: "~900 MB",
            description: "Better quality tags"
        ),
        TagModel(
            id: "mlx-community/Phi-3.5-mini-instruct-4bit",
            name: "Phi-3.5 Mini",
            size: "~2.0 GB",
            description: "High quality, slower"
        ),
    ]
    
    static var defaultModelId: String {
        availableModels.first?.id ?? "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    }
    
    // MARK: - Initialization
    
    init() {
        var continuation: AsyncStream<Double>.Continuation!
        self.loadProgressStream = AsyncStream { continuation = $0 }
        self.progressContinuation = continuation
    }
    
    // MARK: - Model Loading
    
    /// Load the tag extraction model
    func loadModel(modelId: String? = nil) async throws {
        let targetModelId = modelId ?? Self.defaultModelId
        
        // Skip if already loaded with same model
        if modelContainer != nil && currentModelId == targetModelId {
            logger.info("Tag model already loaded: \(targetModelId)")
            return
        }
        
        guard !isLoading else {
            logger.warning("Tag model already loading, skipping")
            return
        }
        
        isLoading = true
        progressContinuation.yield(0.05)
        
        logger.info("Loading tag model: \(targetModelId)")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            // Unload existing model if any
            if modelContainer != nil {
                modelContainer = nil
                currentModelId = nil
            }
            
            progressContinuation.yield(0.1)
            
            // Configure the model - create a custom configuration for the model ID
            let modelConfiguration = ModelConfiguration(id: targetModelId)
            
            // Load model with progress tracking
            modelContainer = try await LLMModelFactory.shared.loadContainer(
                from: HubClient.default,
                configuration: modelConfiguration
            ) { progress in
                let normalizedProgress = 0.1 + (progress.fractionCompleted * 0.9)
                Task { @MainActor in
                    self.progressContinuation.yield(normalizedProgress)
                }
            }
            
            currentModelId = targetModelId
            progressContinuation.yield(1.0)
            
            let loadTime = CFAbsoluteTimeGetCurrent() - startTime
            logger.info("Tag model loaded in \(String(format: "%.2f", loadTime))s: \(targetModelId)")
            
        } catch {
            progressContinuation.yield(0.0)
            logger.error("Failed to load tag model: \(error.localizedDescription)")
            isLoading = false
            throw TagExtractionError.modelLoadFailed(error.localizedDescription)
        }
        
        isLoading = false
    }
    
    /// Unload the model to free memory
    func unloadModel() {
        if let modelId = currentModelId {
            logger.info("Unloading tag model: \(modelId)")
        }
        modelContainer = nil
        currentModelId = nil
    }
    
    // MARK: - Tag Extraction
    
    /// Extract tags from text and app context
    func extractTags(from text: String, appContext: String) async throws -> [String] {
        guard let container = modelContainer else {
            throw TagExtractionError.modelNotLoaded
        }
        
        // Skip very short texts
        guard text.count >= 10 else {
            logger.info("Text too short for tag extraction, skipping")
            return []
        }
        
        let promptText = buildPrompt(text: text, appContext: appContext)
        
        logger.info("Extracting tags from: \(text.prefix(50))...")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            // Create input and parameters for generation
            let input = try await container.prepare(input: .init(prompt: promptText))
            let parameters = GenerateParameters(maxTokens: 60)
            
            // Generate response
            var response = ""
            
            for try await generation in try await container.generate(input: input, parameters: parameters) {
                if let chunk = generation.chunk {
                    response += chunk
                }
                
                // Stop early if we see a newline (tags should be one line)
                if response.contains("\n") {
                    break
                }
            }
            
            let extractTime = CFAbsoluteTimeGetCurrent() - startTime
            logger.info("Tag extraction completed in \(String(format: "%.2f", extractTime))s")
            
            // Parse the response into tags
            let tags = parseTagsFromResponse(response)
            logger.info("Extracted tags: \(tags.joined(separator: ", "))")
            
            return tags
            
        } catch {
            logger.error("Tag extraction failed: \(error.localizedDescription)")
            throw TagExtractionError.extractionFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Private Helpers
    
    private func buildPrompt(text: String, appContext: String) -> String {
        """
        Extract 3-5 relevant tags from this transcription. The user was in \(appContext) when speaking.
        
        Return ONLY lowercase tags separated by commas. No hashtags, no explanations, no numbering.
        
        Transcription: "\(text)"
        
        Tags:
        """
    }
    
    private func parseTagsFromResponse(_ response: String) -> [String] {
        // Clean up the response
        var cleaned = response
            .lowercased()
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common prefixes the model might add
        let prefixes = ["tags:", "here are", "the tags are", "extracted tags:"]
        for prefix in prefixes {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Split by comma and clean each tag
        let tags = cleaned
            .split(separator: ",")
            .map { tag -> String in
                var t = String(tag).trimmingCharacters(in: .whitespacesAndNewlines)
                // Remove numbering like "1.", "2.", etc.
                if let dotIndex = t.firstIndex(of: "."), t.distance(from: t.startIndex, to: dotIndex) <= 2 {
                    t = String(t[t.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
                }
                return t
            }
            .filter { tag in
                // Validate tag
                !tag.isEmpty &&
                tag.count >= 2 &&
                tag.count <= 30 &&
                !tag.contains(" ") || tag.split(separator: " ").count <= 3 // Allow up to 3-word phrases
            }
            .map { $0.replacingOccurrences(of: " ", with: "-") } // Convert spaces to hyphens
        
        // Return unique tags, limited to 5
        return Array(Set(tags)).sorted().prefix(5).map { String($0) }
    }
}

// MARK: - Errors

enum TagExtractionError: LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(String)
    case extractionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Tag extraction model is not loaded"
        case .modelLoadFailed(let message):
            return "Failed to load tag model: \(message)"
        case .extractionFailed(let message):
            return "Tag extraction failed: \(message)"
        }
    }
}
