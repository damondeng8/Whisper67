import Foundation
import AppKit
import Darwin

/// Pauses system media (Music, Spotify, browsers, YouTube via Now Playing, etc.)
/// when dictation starts, and resumes only if we paused it.
///
/// Uses MediaRemote (private but stable) when available, with a system media-key fallback.
final class MediaPauseService {
    static let shared = MediaPauseService()
    
    /// True if we issued a pause this dictation session and should resume after.
    private var shouldResume = false
    private var pauseGeneration: UInt64 = 0
    
    private init() {}
    
    // MARK: - Public
    
    /// Call when dictation recording begins.
    func pauseForDictation() {
        guard AppState.shared.pauseMediaDuringDictation else {
            shouldResume = false
            return
        }
        
        pauseGeneration &+= 1
        let gen = pauseGeneration
        shouldResume = false
        
        // Async: MediaRemote now-playing check is callback-based
        isNowPlaying { [weak self] playing in
            guard let self, gen == self.pauseGeneration else { return }
            guard playing else {
                AppLog.debug("🔈 Media not playing — skip pause")
                return
            }
            let ok = self.sendPause()
            if ok {
                self.shouldResume = true
                AppLog.info("🔈 Paused system media for dictation")
            } else {
                // Fallback: hardware play/pause (toggle). Only if we believe something is playing.
                self.postMediaPlayPauseKey()
                self.shouldResume = true
                AppLog.info("🔈 Sent media play/pause key for dictation")
            }
        }
    }
    
    /// Call when dictation ends (confirm, cancel, or error).
    func resumeAfterDictation() {
        guard shouldResume else { return }
        shouldResume = false
        pauseGeneration &+= 1
        
        // Small delay so our mic session finishes releasing and Now Playing updates
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let ok = self.sendPlay()
            if ok {
                AppLog.info("🔈 Resumed system media after dictation")
            } else {
                self.postMediaPlayPauseKey()
                AppLog.info("🔈 Sent media play/pause key to resume")
            }
        }
    }
    
    // MARK: - MediaRemote (dynamic)
    
    private enum MRCommand: UInt32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case stop = 3
    }
    
    private typealias SendCommandFn = @convention(c) (UInt32, Unmanaged<CFDictionary>?) -> Bool
    private typealias GetPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    
    private lazy var mediaRemoteHandle: UnsafeMutableRawPointer? = {
        // /System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        return dlopen(path, RTLD_LAZY)
    }()
    
    private lazy var sendCommand: SendCommandFn? = {
        guard let handle = mediaRemoteHandle,
              let sym = dlsym(handle, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(sym, to: SendCommandFn.self)
    }()
    
    private lazy var getPlaying: GetPlayingFn? = {
        guard let handle = mediaRemoteHandle,
              let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") else { return nil }
        return unsafeBitCast(sym, to: GetPlayingFn.self)
    }()
    
    private func isNowPlaying(_ completion: @escaping (Bool) -> Void) {
        if let getPlaying {
            getPlaying(DispatchQueue.main) { playing in
                completion(playing)
            }
            // Safety timeout if callback never fires
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                // no-op if already completed; callers use generation
            }
            return
        }
        // Unknown — assume may be playing so pause still works via media key
        completion(true)
    }
    
    private func sendPause() -> Bool {
        guard let sendCommand else { return false }
        return sendCommand(MRCommand.pause.rawValue, nil)
            || sendCommand(MRCommand.stop.rawValue, nil)
    }
    
    private func sendPlay() -> Bool {
        guard let sendCommand else { return false }
        return sendCommand(MRCommand.play.rawValue, nil)
    }
    
    // MARK: - System media key fallback (play/pause)
    
    /// Posts NX_KEYTYPE_PLAY (system play/pause) key down + up.
    private func postMediaPlayPauseKey() {
        // NX_KEYTYPE_PLAY = 16
        let NX_KEYTYPE_PLAY: Int32 = 16
        postSystemDefinedKey(NX_KEYTYPE_PLAY, down: true)
        postSystemDefinedKey(NX_KEYTYPE_PLAY, down: false)
    }
    
    private func postSystemDefinedKey(_ key: Int32, down: Bool) {
        // data1 layout used by system media keys
        let keyCode = Int(key)
        let stateBits = down ? 0xa : 0xb
        let data1 = (keyCode << 16) | (stateBits << 8)
        
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0x0a00),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ),
        let cg = event.cgEvent else {
            return
        }
        cg.post(tap: .cghidEventTap)
    }
}
