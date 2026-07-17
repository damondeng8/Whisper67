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
    /// Multi-band 0…1 levels for the waveform bars
    private(set) var audioBands: [Float] = Array(repeating: 0, count: 24)
    
    var onAudioLevelUpdate: ((Float) -> Void)?
    var onAudioBandsUpdate: (([Float]) -> Void)?
    
    let bandCount = 24
    
    private let audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var recordingStartTime: Date?
    
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
    
    // MARK: - Permission (hardened-runtime safe)
    
    /// Current mic authorization. Prefer AVAudioApplication on macOS 14+.
    static func microphoneAuthorized() -> Bool {
        #if os(macOS)
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return true
            case .denied: return false
            case .undetermined: break
            @unknown default: break
            }
        }
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        #else
        return false
        #endif
    }
    
    static func requestMicrophoneAccess() async -> Bool {
        #if os(macOS)
        if #available(macOS 14.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
        }
        #else
        return false
        #endif
    }
    
    // MARK: - Record
    
    func start() throws -> URL {
        if isRecording {
            _ = stop()
        }
        
        #if os(macOS)
        // Refresh permission; if undetermined, caller should have requested already
        guard Self.microphoneAuthorized() else {
            throw NSError(
                domain: "AudioRecorderService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Microphone permission not granted. Enable Whisper67 in System Settings → Privacy & Security → Microphone."]
            )
        }
        #endif
        
        // Fully reset engine between sessions
        teardownEngine()
        
        let input = audioEngine.inputNode
        inputNode = input
        
        // Prepare engine so hardware formats resolve (0 Hz is common before prepare/start)
        audioEngine.prepare()
        
        var hwFormat = input.inputFormat(forBus: 0)
        if hwFormat.sampleRate < 1 || hwFormat.channelCount < 1 {
            hwFormat = input.outputFormat(forBus: 0)
        }
        
        // Last resort: pick default input device rate
        if hwFormat.sampleRate < 1 || hwFormat.channelCount < 1 {
            let rate = Self.defaultInputSampleRate()
            guard let fallback = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: rate,
                channels: 1,
                interleaved: false
            ) else {
                throw NSError(
                    domain: "AudioRecorderService",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Could not create audio format — check that a microphone is connected"]
                )
            }
            hwFormat = fallback
            print("⚠️ Using fallback audio format \(rate) Hz mono")
        }
        
        print("🎤 Hardware format: \(hwFormat.sampleRate) Hz, \(hwFormat.channelCount) ch, \(hwFormat.commonFormat.rawValue)")
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper67_\(UUID().uuidString).wav")
        
        // Always write mono float32 at hardware sample rate for reliable Whisper upload
        let writeRate = hwFormat.sampleRate
        guard let writeFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: writeRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(
                domain: "AudioRecorderService",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Could not create write format"]
            )
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: writeRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true
        ]
        
        audioFile = try AVAudioFile(forWriting: url, settings: settings)
        recordingURL = url
        
        // format: nil = use the input node's native format (critical on macOS)
        // Avoid installing with a mismatched format which yields silence / crash
        input.removeTap(onBus: 0)
        
        let converter: AVAudioConverter? = {
            let native = input.outputFormat(forBus: 0).sampleRate > 0
                ? input.outputFormat(forBus: 0)
                : hwFormat
            if native.channelCount == 1,
               native.commonFormat == .pcmFormatFloat32,
               abs(native.sampleRate - writeRate) < 0.5 {
                return nil
            }
            return AVAudioConverter(from: native, to: writeFormat)
        }()
        
        input.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            
            // Convert to mono float if needed, else write directly
            if let converter {
                let frameCapacity = AVAudioFrameCount(
                    Double(buffer.frameLength) * writeFormat.sampleRate / buffer.format.sampleRate
                ) + 32
                guard let out = AVAudioPCMBuffer(pcmFormat: writeFormat, frameCapacity: max(1, frameCapacity)) else {
                    self.processLevel(buffer)
                    return
                }
                var error: NSError?
                var consumed = false
                let status = converter.convert(to: out, error: &error) { _, outStatus in
                    if consumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    consumed = true
                    outStatus.pointee = .haveData
                    return buffer
                }
                if status != .error, out.frameLength > 0 {
                    try? self.audioFile?.write(from: out)
                    self.processLevel(out)
                } else {
                    if let error { print("Audio convert error: \(error)") }
                    self.processLevel(buffer)
                }
            } else {
                do {
                    try self.audioFile?.write(from: buffer)
                } catch {
                    print("Audio write error: \(error)")
                }
                self.processLevel(buffer)
            }
        }
        
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            audioFile = nil
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
            print("❌ AVAudioEngine.start failed: \(error)")
            throw NSError(
                domain: "AudioRecorderService",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Could not start microphone: \(error.localizedDescription). Check System Settings → Privacy & Security → Microphone for Whisper67."]
            )
        }
        
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
        teardownEngine()
        // Close file handle before reading
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
            if size < 1000 {
                print("⚠️ Recording file is very small — mic may not have captured audio")
            }
        }
        return (url, duration)
    }
    
    func cancel() {
        let result = stop()
        if let url = result.url {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private func teardownEngine() {
        if let inputNode {
            inputNode.removeTap(onBus: 0)
        } else {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()
        inputNode = nil
    }
    
    private static func defaultInputSampleRate() -> Double {
        // Try to read default input device nominal rate via AVCapture if available
        #if os(macOS)
        if let device = AVCaptureDevice.default(for: .audio) {
            // common rates; device doesn't expose rate easily — use 48k
            _ = device
        }
        #endif
        return 48_000
    }
    
    // MARK: - Metering
    
    private func processLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        
        let channels = Int(buffer.format.channelCount)
        // Mixdown if multi-channel
        var mono = [Float](repeating: 0, count: frameLength)
        if channels <= 1 {
            mono = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        } else {
            for c in 0..<channels {
                let samples = UnsafeBufferPointer(start: channelData[c], count: frameLength)
                for i in 0..<frameLength {
                    mono[i] += samples[i]
                }
            }
            let inv = 1.0 / Float(channels)
            for i in 0..<frameLength { mono[i] *= inv }
        }
        
        var sumSquares: Float = 0
        vDSP_svesq(mono, 1, &sumSquares, vDSP_Length(frameLength))
        let rms = sqrt(sumSquares / Float(frameLength))
        
        var peak: Float = 0
        vDSP_maxmgv(mono, 1, &peak, vDSP_Length(frameLength))
        
        let overall = loudnessUnit(rms * 0.88 + peak * 0.12)
        
        var bands = [Float](repeating: 0, count: bandCount)
        let slice = max(1, frameLength / bandCount)
        for i in 0..<bandCount {
            let start = i * slice
            let end = min(frameLength, start + slice)
            guard end > start else { continue }
            let count = end - start
            var sliceSum: Float = 0
            mono.withUnsafeBufferPointer { buf in
                vDSP_svesq(buf.baseAddress!.advanced(by: start), 1, &sliceSum, vDSP_Length(count))
            }
            bands[i] = loudnessUnit(sqrt(sliceSum / Float(count)))
        }
        
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
    
    private func loudnessUnit(_ linear: Float) -> Float {
        let floor: Float = 0.0012
        let ceiling: Float = 0.12
        let clamped = max(floor, min(ceiling, linear))
        let minDb = 20 * log10(floor)
        let maxDb = 20 * log10(ceiling)
        let db = 20 * log10(clamped)
        let unit = (db - minDb) / (maxDb - minDb)
        return max(0, min(1, pow(unit, 1.05) * 1.15))
    }
}
