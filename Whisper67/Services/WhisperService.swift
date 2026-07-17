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
    /// Bumped on cancel so in-flight STT/OSS results are discarded (no paste).
    private var jobID: UInt64 = 0
    /// Floor so accidental blips still fail fast without padding real utterances.
    private let minimumRecordingDuration: TimeInterval = 0.18
    
    /// Typed completion (success or failure). Prefer this over stringly errors.
    var onOutcome: ((TranscriptionOutcome) -> Void)?
    var onAudioLevelUpdate: ((Float) -> Void)?
    /// Multi-band levels for the live waveform (same count as UI bars)
    var onAudioBandsUpdate: (([Float]) -> Void)?
    
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
        if !AudioRecorderService.microphoneAuthorized() {
            Task {
                let granted = await AudioRecorderService.requestMicrophoneAccess()
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
        
        jobID &+= 1
        let myJob = jobID
        
        let (url, duration) = recorder.stop()
        guard let url else {
            await finish(job: myJob, error: "No recording captured", duration: 0)
            return
        }
        
        if duration < minimumRecordingDuration {
            try? FileManager.default.removeItem(at: url)
            await finish(job: myJob, error: "Recording too short", duration: duration)
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
                    await finish(job: myJob, error: "No audio detected", duration: duration)
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
            
            guard myJob == jobID else {
                print("⏭ Discarded stale transcription job \(myJob)")
                return
            }
            
            let styled = await finalizeTranscript(text, appState: appState)
            
            guard myJob == jobID else {
                print("⏭ Discarded stale transcription job \(myJob) after polish")
                return
            }
            
            await MainActor.run {
                transcribedText = styled
                isTranscribing = false
                onOutcome?(.success(text: styled, durationSeconds: audioSeconds))
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            AppLog.info("❌ Transcription failed: \(error)")
            await finish(job: myJob, error: error.localizedDescription, duration: duration)
        }
    }
    
    /// One place for list detect → optional OSS → style (keeps pipeline readable).
    private func finalizeTranscript(_ text: String, appState: AppState) async -> String {
        let listDetection = ListDetector.analyze(text)
        let listLikely = appState.listModeEnabled && listDetection.isLikelyList
        
        let runOSS = appState.canRunAIPolish
            || (appState.listModeEnabled && appState.hasGroqKey && listDetection.isLikelyList)
        
        if runOSS {
            let strength = appState.canRunAIPolish
                ? appState.aiPolishStrength
                : min(appState.aiPolishStrength, 0.30)
            let polished = await TranscriptCleanupService.polish(
                text,
                style: appState.dictationStyle,
                listModeEnabled: appState.listModeEnabled,
                listLikely: listLikely,
                dictionaryWords: appState.customWords.map(\.word),
                groqAPIKey: appState.groqKey,
                strength: strength
            )
            // Prefer OSS wording; always enforce local style (list markers preserved)
            let base = polished == text
                ? text
                : polished.trimmingCharacters(in: .whitespacesAndNewlines)
            return TranscriptFormatter.format(
                base,
                style: appState.dictationStyle,
                listMode: listLikely && polished == text
            )
        }
        
        return appState.formatTranscript(text, forceList: listLikely)
    }
    
    private func finish(job: UInt64, error: String, duration: Double) async {
        guard job == jobID else { return }
        await MainActor.run {
            isTranscribing = false
            onOutcome?(.failure(message: error, durationSeconds: duration))
        }
    }
    
    func cancelRecording() {
        jobID &+= 1 // invalidate any in-flight stopAndTranscribe
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
                // Style/dictionary applied in finalizeTranscript (formatter + optional OSS)
                return text
            }
        }
        return "No speech detected"
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
