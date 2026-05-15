import Foundation
import AVFoundation

/// Captures audio from the microphone in Whisper-compatible format (16kHz mono Float32)
actor AudioCaptureService {
    private var audioEngine: AVAudioEngine?
    private var audioBuffers: [Float] = []
    private var isCurrentlyRecording = false
    
    // Whisper requires 16kHz sample rate
    private let targetSampleRate: Double = 16000
    
    var isRecording: Bool {
        isCurrentlyRecording
    }
    
    func startRecording() async throws {
        // Force-reset stale state (can happen after a crash or forced stop from Xcode)
        if isCurrentlyRecording {
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            audioEngine = nil
            isCurrentlyRecording = false
        }

        audioBuffers.removeAll()
        
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Create converter format for 16kHz mono
        guard let converterFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatError
        }
        
        // Create converter if sample rates differ
        let converter: AVAudioConverter?
        if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
            converter = AVAudioConverter(from: inputFormat, to: converterFormat)
        } else {
            converter = nil
        }
        
        // Install tap on input node
        // All non-Sendable audio processing (buffer, converter) happens
        // synchronously in the tap callback; only Sendable [Float] crosses
        // the actor boundary.
        let localConverter = converter
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            // Extract + convert samples synchronously on the audio thread
            let finalSamples = Self.extractSamples(
                from: buffer,
                converter: localConverter,
                targetSampleRate: 16000,
                outputFormat: converterFormat
            )
            guard let finalSamples else { return }
            guard let self else { return }
            
            Task { [finalSamples] in
                await self.appendSamples(finalSamples)
            }
        }
        
        engine.prepare()
        try engine.start()
        
        self.audioEngine = engine
        isCurrentlyRecording = true
    }
    
    func stopRecording() async -> AudioData {
        isCurrentlyRecording = false
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        let samples = audioBuffers
        audioBuffers.removeAll()
        
        return AudioData(samples: samples)
    }
    
    /// Synchronously extract and convert float samples from an AVAudioPCMBuffer.
    /// All non-Sendable types stay within this static method; only [Float] crosses actor boundaries.
    private nonisolated static func extractSamples(
        from buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter?,
        targetSampleRate: Double,
        outputFormat: AVAudioFormat
    ) -> [Float]? {
        if let converter = converter {
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate
            )
            
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: frameCapacity
            ) else { return nil }
            
            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            guard status != .error, let channelData = convertedBuffer.floatChannelData?[0] else {
                return nil
            }
            
            return Array(UnsafeBufferPointer(
                start: channelData,
                count: Int(convertedBuffer.frameLength)
            ))
        } else {
            // Already in correct format
            guard let channelData = buffer.floatChannelData?[0] else { return nil }
            return Array(UnsafeBufferPointer(
                start: channelData,
                count: Int(buffer.frameLength)
            ))
        }
    }
    
    /// Append extracted float samples to the recording buffer (actor-isolated)
    private func appendSamples(_ samples: [Float]) {
        guard isCurrentlyRecording else { return }
        audioBuffers.append(contentsOf: samples)
    }
}

// MARK: - Errors
enum AudioCaptureError: LocalizedError {
    case alreadyRecording
    case formatError
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Recording is already in progress"
        case .formatError:
            return "Failed to configure audio format"
        case .permissionDenied:
            return "Microphone permission denied"
        }
    }
}
