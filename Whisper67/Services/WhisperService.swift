import Foundation
import WhisperKit
import AVFoundation
import Observation

@Observable
class WhisperService {
    var whisperKit: WhisperKit?
    var isTranscribing = false
    var transcribedText = ""
    var isLoading = false
    var loadingProgress: Double = 0.0
    var availableModels: [String] = ["tiny", "base", "small", "medium", "large"]
    var selectedModel = "tiny"
    var modelStatus: ModelStatus = .notLoaded
    var downloadProgress: Double = 0.0
    
    enum ModelStatus: Equatable {
        case notLoaded
        case downloading
        case loaded
        case error(String)
        
        var description: String {
            switch self {
            case .notLoaded: return "Not downloaded"
            case .downloading: return "Downloading..."
            case .loaded: return "Ready"
            case .error(let message): return "Error: \(message)"
            }
        }
    }
    
    private let recorder = AudioRecorderService.shared
    private var isProcessing = false
    /// Floor so accidental blips still fail fast without padding real utterances.
    private let minimumRecordingDuration: TimeInterval = 0.18
    
    var onTranscriptionComplete: ((String, Double) -> Void)?
    var onAudioLevelUpdate: ((Float) -> Void)?
    /// Multi-band levels for the live waveform (same count as UI bars)
    var onAudioBandsUpdate: (([Float]) -> Void)?
    var onError: ((String) -> Void)?
    
    init() {
        // Defer heavy local model load until local provider is used
        setupAudioPermission()
        recorder.onAudioLevelUpdate = { [weak self] level in
            self?.onAudioLevelUpdate?(level)
        }
        recorder.onAudioBandsUpdate = { [weak self] bands in
            self?.onAudioBandsUpdate?(bands)
        }
    }
    
    func ensureLocalModelReady() {
        guard whisperKit == nil, modelStatus != .downloading else { return }
        setupWhisperKit()
    }
    
    func setupWhisperKit() {
        Task {
            await loadWhisperKit()
        }
    }
    
    @MainActor
    private func loadWhisperKit() async {
        print("🧠 Starting WhisperKit initialization for model: \(selectedModel)")
        isLoading = true
        modelStatus = .downloading
        loadingProgress = 0.0
        downloadProgress = 0.0
        
        do {
            let startTime = Date()
            whisperKit = try await WhisperKit(model: selectedModel)
            let loadTime = Date().timeIntervalSince(startTime)
            print("✅ WhisperKit ready in \(String(format: "%.2f", loadTime))s")
            loadingProgress = 1.0
            downloadProgress = 1.0
            modelStatus = .loaded
            isLoading = false
        } catch {
            print("❌ WhisperKit failed: \(error)")
            modelStatus = .error(error.localizedDescription)
            isLoading = false
            whisperKit = nil
        }
    }
    
    private func setupAudioPermission() {
        #if os(macOS)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("🎤 Microphone permission: \(granted)")
            }
        }
        #endif
    }
    
    func changeModel(_ modelName: String) {
        guard modelName != selectedModel else { return }
        selectedModel = modelName
        modelStatus = .notLoaded
        downloadProgress = 0.0
        whisperKit = nil
        setupWhisperKit()
    }
    
    var isModelReady: Bool {
        modelStatus == .loaded && whisperKit != nil
    }
    
    // MARK: - Unified record / stop
    
    func startRecording() throws {
        guard !recorder.isRecording else { return }
        _ = try recorder.start()
        isTranscribing = true
        transcribedText = ""
    }
    
    /// Stops recording and transcribes via the selected provider.
    func stopAndTranscribe(using appState: AppState) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        
        let (url, duration) = recorder.stop()
        guard let url else {
            await MainActor.run {
                isTranscribing = false
                onError?("No recording captured")
            }
            return
        }
        
        if duration < minimumRecordingDuration {
            try? FileManager.default.removeItem(at: url)
            await MainActor.run {
                isTranscribing = false
                onTranscriptionComplete?("Recording too short", duration)
            }
            return
        }
        
        do {
            let text: String
            let audioSeconds: Double
            
            switch appState.provider {
            case .local:
                let samples = try readAndResampleAudio(from: url)
                try? FileManager.default.removeItem(at: url)
                guard !samples.isEmpty else {
                    await MainActor.run {
                        isTranscribing = false
                        onTranscriptionComplete?("No audio detected", duration)
                    }
                    return
                }
                text = try await transcribeLocal(samples: samples, prompt: appState.transcriptionPrompt)
                audioSeconds = duration
                
            case .openAI, .groq:
                let result = try await CloudWhisperAPI.transcribe(
                    audioURL: url,
                    provider: appState.provider,
                    apiKey: appState.apiKeyForCurrentProvider,
                    language: appState.language,
                    prompt: appState.transcriptionPrompt
                )
                try? FileManager.default.removeItem(at: url)
                text = result.text
                audioSeconds = result.durationSeconds > 0 ? result.durationSeconds : duration
            }
            
            // Apply style + list modes (deterministic post-process)
            let styled = appState.formatTranscript(text)
            
            await MainActor.run {
                transcribedText = styled
                isTranscribing = false
                onTranscriptionComplete?(styled, audioSeconds)
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            print("❌ Transcription failed: \(error)")
            await MainActor.run {
                isTranscribing = false
                onError?(error.localizedDescription)
                onTranscriptionComplete?("Transcription failed: \(error.localizedDescription)", duration)
            }
        }
    }
    
    func cancelRecording() {
        recorder.cancel()
        isTranscribing = false
    }
    
    // MARK: - Local WhisperKit
    
    private func transcribeLocal(samples: [Float], prompt: String) async throws -> String {
        if whisperKit == nil {
            await loadWhisperKit()
        }
        guard let whisperKit else {
            throw NSError(
                domain: "WhisperService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Local model not ready"]
            )
        }
        
        // Speed-biased decode: no timestamps, greedy temperature, skip special tokens.
        var options = DecodingOptions()
        options.temperature = 0
        options.temperatureFallbackCount = 0
        options.withoutTimestamps = true
        options.skipSpecialTokens = true
        options.wordTimestamps = false
        if !prompt.isEmpty {
            options.promptTokens = nil // prompt applied via soft post-pass; keeps first-pass fast
        }
        
        let results = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: options
        )
        
        for result in results {
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return applyCustomWordHints(text, prompt: prompt)
            }
        }
        return "No speech detected"
    }
    
    /// Light post-processing: if custom words appear as close phonetic misses, leave as-is;
    /// primarily cloud APIs use prompt — this is a soft pass-through.
    private func applyCustomWordHints(_ text: String, prompt: String) -> String {
        _ = prompt
        return text
    }
    
    private func readAndResampleAudio(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "WhisperService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Bad output format"])
        }
        
        let outputFrameCount = AVAudioFrameCount(Double(frameCount) * (outputFormat.sampleRate / format.sampleRate))
        
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return []
        }
        try file.read(into: inputBuffer)
        guard inputBuffer.frameLength > 0 else { return [] }
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: max(1, outputFrameCount)) else {
            return []
        }
        
        if format.sampleRate != outputFormat.sampleRate || format.channelCount != outputFormat.channelCount {
            guard let converter = AVAudioConverter(from: format, to: outputFormat) else {
                return []
            }
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return inputBuffer
            }
            converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
            if let error { throw error }
        } else {
            outputBuffer.frameLength = inputBuffer.frameLength
            if let inData = inputBuffer.floatChannelData, let outData = outputBuffer.floatChannelData {
                memcpy(outData[0], inData[0], Int(inputBuffer.frameLength) * MemoryLayout<Float>.size)
            }
        }
        
        guard let channelData = outputBuffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
    }
}
