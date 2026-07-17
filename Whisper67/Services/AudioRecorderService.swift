import Foundation
import AVFoundation
import Observation
import Accelerate

/// Shared microphone recorder used by both local WhisperKit and cloud APIs.
@Observable
final class AudioRecorderService {
    static let shared = AudioRecorderService()
    
    private(set) var isRecording = false
    /// Overall 0…1 loudness (speech-normalized)
    private(set) var audioLevel: Float = 0
    /// Multi-band 0…1 levels for the waveform bars (time-domain slices of the latest buffer)
    private(set) var audioBands: [Float] = Array(repeating: 0, count: 24)
    
    var onAudioLevelUpdate: ((Float) -> Void)?
    /// Fired with barCount band levels each audio callback (~realtime)
    var onAudioBandsUpdate: (([Float]) -> Void)?
    
    /// Number of waveform bars (keep in sync with UI)
    let bandCount = 24
    
    private let audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var recordingStartTime: Date?
    
    /// Smoothing so the UI doesn't flicker
    private var smoothedOverall: Float = 0
    private var smoothedBands: [Float] = Array(repeating: 0, count: 24)
    
    private init() {
        smoothedBands = Array(repeating: 0, count: bandCount)
        audioBands = smoothedBands
    }
    
    var recordingDuration: TimeInterval {
        guard let start = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
    
    func start() throws -> URL {
        if isRecording {
            _ = stop()
        }
        
        #if os(macOS)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            throw NSError(
                domain: "AudioRecorderService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Microphone permission not granted"]
            )
        }
        #endif
        
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()
        
        let input = audioEngine.inputNode
        inputNode = input
        
        var format = input.inputFormat(forBus: 0)
        if format.sampleRate == 0 || format.channelCount == 0 {
            format = input.outputFormat(forBus: 0)
        }
        if format.sampleRate == 0 || format.channelCount == 0 {
            guard let fallback = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 1,
                interleaved: false
            ) else {
                throw NSError(
                    domain: "AudioRecorderService",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Could not create audio format"]
                )
            }
            format = fallback
            print("⚠️ Using fallback audio format 48kHz mono")
        }
        
        print("🎤 Recording format: \(format.sampleRate) Hz, \(format.channelCount) ch")
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper67_\(UUID().uuidString).wav")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: !format.isInterleaved
        ]
        
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: settings)
        } catch {
            audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        }
        recordingURL = url
        
        input.removeTap(onBus: 0)
        
        let tapFormat = input.outputFormat(forBus: 0).sampleRate > 0
            ? input.outputFormat(forBus: 0)
            : format
        
        // Smaller buffer = snappier waveform (~10–20 ms at 48 kHz)
        let bufferSize: AVAudioFrameCount = 1024
        
        input.installTap(onBus: 0, bufferSize: bufferSize, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            do {
                try self.audioFile?.write(from: buffer)
            } catch {
                print("Audio write error: \(error)")
            }
            self.processLevel(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        recordingStartTime = Date()
        isRecording = true
        smoothedOverall = 0
        smoothedBands = Array(repeating: 0, count: bandCount)
        print("✅ Audio engine started → \(url.lastPathComponent)")
        return url
    }
    
    @discardableResult
    func stop() -> (url: URL?, duration: TimeInterval) {
        let duration = recordingDuration
        if let inputNode {
            inputNode.removeTap(onBus: 0)
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioFile = nil
        isRecording = false
        audioLevel = 0
        audioBands = Array(repeating: 0, count: bandCount)
        smoothedOverall = 0
        smoothedBands = Array(repeating: 0, count: bandCount)
        recordingStartTime = nil
        let url = recordingURL
        recordingURL = nil
        
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevelUpdate?(0)
            self?.onAudioBandsUpdate?(Array(repeating: 0, count: self?.bandCount ?? 24))
        }
        
        if let url {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            print("🛑 Recording stopped: \(String(format: "%.2f", duration))s, \(size) bytes")
        }
        return (url, duration)
    }
    
    func cancel() {
        let result = stop()
        if let url = result.url {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    // MARK: - Metering (real mic → overall + light texture)
    
    private func processLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        
        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)
        
        // Overall RMS (primary driver for Wispr-style center wave)
        var sumSquares: Float = 0
        vDSP_svesq(samples.baseAddress!, 1, &sumSquares, vDSP_Length(frameLength))
        let rms = sqrt(sumSquares / Float(frameLength))
        
        // Soft peak (don't let clicks dominate)
        var peak: Float = 0
        vDSP_maxmgv(samples.baseAddress!, 1, &peak, vDSP_Length(frameLength))
        
        // Blend RMS heavy + mild peak so speech feels full without spiking on noise
        let overall = loudnessUnit(rms * 0.88 + peak * 0.12)
        
        // Coarse texture only (for slight organic variation in shaper — not the main shape)
        var bands = [Float](repeating: 0, count: bandCount)
        let slice = max(1, frameLength / bandCount)
        for i in 0..<bandCount {
            let start = i * slice
            let end = min(frameLength, start + slice)
            guard end > start else { continue }
            let count = end - start
            var sliceSum: Float = 0
            vDSP_svesq(samples.baseAddress!.advanced(by: start), 1, &sliceSum, vDSP_Length(count))
            let sliceRms = sqrt(sliceSum / Float(count))
            bands[i] = loudnessUnit(sliceRms)
        }
        
        // Gentle smoothing — slower than before (less twitchy)
        let attack: Float = 0.28
        let release: Float = 0.12
        let alpha = overall > smoothedOverall ? attack : release
        smoothedOverall = smoothedOverall * (1 - alpha) + overall * alpha
        
        for i in 0..<bandCount {
            let a = bands[i] > smoothedBands[i] ? attack : release
            smoothedBands[i] = smoothedBands[i] * (1 - a) + bands[i] * a
        }
        
        let outOverall = smoothedOverall
        let outBands = smoothedBands
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.audioLevel = outOverall
            self.audioBands = outBands
            self.onAudioLevelUpdate?(outOverall)
            self.onAudioBandsUpdate?(outBands)
        }
    }
    
    /// Map linear RMS → 0…1 (~2× more sensitive than previous curve).
    private func loudnessUnit(_ linear: Float) -> Float {
        let floor: Float = 0.0012
        let ceiling: Float = 0.12
        let clamped = max(floor, min(ceiling, linear))
        let minDb = 20 * log10(floor)
        let maxDb = 20 * log10(ceiling)
        let db = 20 * log10(clamped)
        let unit = (db - minDb) / (maxDb - minDb)
        // Milder gamma + slight boost for normal speech
        return max(0, min(1, pow(unit, 1.05) * 1.15))
    }
}
