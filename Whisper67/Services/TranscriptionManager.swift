import Foundation
import SwiftUI
import AVFoundation
import Observation

@Observable
final class TranscriptionManager {
    static let shared = TranscriptionManager()
    
    private let whisperService = WhisperService()
    private let clipboardService = ClipboardService.shared
    private let controlInput = ControlDictationInput.shared
    private let globalHotkey = GlobalHotkeyService.shared
    private let sessionKeys = RecordingKeyMonitor.shared
    private let overlayManager = TranscriptionOverlayManager.shared
    private let appState = AppState.shared
    
    var isTranscribing = false
    var isStickySession = false
    var lastError: String?
    var lastTranscript: String = ""
    var statusMessage: String = "Ready"
    /// Live mic loudness 0…1 for Home preview waveform
    var liveAudioLevel: Float = 0
    var liveAudioBands: [Float] = Array(repeating: 0, count: 24)
    
    /// Exposed for settings UI
    var localWhisper: WhisperService { whisperService }
    /// Status for Home permission rows
    var hotkey: HotkeyStatusProxy {
        HotkeyStatusProxy(control: controlInput, global: globalHotkey)
    }
    
    private var isConfirming = false
    /// Prevents double paste if completion is delivered twice.
    private var lastCompletedFingerprint: String = ""
    private var lastCompletedAt: Date = .distantPast
    
    private init() {
        setupServices()
    }
    
    private func setupServices() {
        // Control hold / double-tap (⌃ only — Enter/Esc via sessionKeys)
        controlInput.onStart = { [weak self] in
            Task { @MainActor in
                await self?.beginDictation(sticky: ControlDictationInput.shared.isSticky)
            }
        }
        controlInput.onConfirm = { [weak self] in
            Task { @MainActor in
                await self?.confirmDictation()
            }
        }
        
        // Sole Enter / Esc owner while any session is open
        sessionKeys.onConfirm = { [weak self] in
            Task { @MainActor in
                AppLog.debug("⏎ sessionKeys confirm sticky=\(self?.isStickySession ?? false)")
                await self?.confirmDictation()
            }
        }
        sessionKeys.onCancel = { [weak self] in
            Task { @MainActor in
                await self?.cancelTranscription()
            }
        }
        
        // Classic keyboard shortcut (⌥Space, F5, ⌘⇧D, …)
        globalHotkey.currentHotkey = appState.hotkey
        globalHotkey.onHotkeyPressed = { [weak self] in
            Task { @MainActor in
                await self?.handleCustomHotkey()
            }
        }
        
        whisperService.onOutcome = { [weak self] outcome in
            self?.handleOutcome(outcome)
        }
        
        whisperService.onAudioLevelUpdate = { [weak self] level in
            self?.liveAudioLevel = level
            self?.overlayManager.updateAudioLevel(level)
        }
        whisperService.onAudioBandsUpdate = { [weak self] bands in
            self?.liveAudioBands = bands
            self?.overlayManager.updateAudioBands(bands)
        }
        
        controlInput.setup()
        globalHotkey.setup()
        
        NotificationCenter.default.addObserver(
            forName: .whisper67ToggleDictation,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.toggleDictation()
            }
        }
        
        // Keep WhisperService model in sync with Settings (tiny is fastest default)
        if whisperService.selectedModel != appState.localModel {
            whisperService.selectedModel = appState.localModel
        }
        if appState.provider == .local {
            whisperService.ensureLocalModelReady()
        }
        
        updateStatusMessage()
    }
    
    func updateHotkey(_ hotkey: String) {
        appState.hotkey = hotkey
        globalHotkey.currentHotkey = hotkey
        globalHotkey.setup()
        updateStatusMessage()
    }
    
    func setControlPushToTalkEnabled(_ enabled: Bool) {
        appState.controlPushToTalkEnabled = enabled
        if !enabled {
            controlInput.resetSessionFlags()
        }
        updateStatusMessage()
    }
    
    func providerChanged() {
        if appState.provider == .local {
            whisperService.ensureLocalModelReady()
        }
        updateStatusMessage()
    }
    
    func updateStatusMessage() {
        if appState.provider.isCloud && !appState.isProviderConfigured {
            statusMessage = "Add a \(appState.provider.displayName) API key in the API tab"
        } else if appState.provider == .local && !whisperService.isModelReady {
            statusMessage = "Loading local model…"
        } else if isTranscribing {
            statusMessage = isStickySession
                ? "Sticky · ⏎ Enter or \(appState.hotkey) to send · Esc / ✕ cancel"
                : (appState.controlPushToTalkEnabled
                   ? "Release ⌃ to send · or ⏎ Enter"
                   : "⏎ Enter to send · Esc cancel")
        } else if appState.controlPushToTalkEnabled {
            statusMessage = "\(appState.hotkey) · hold ⌃ · \(appState.modeStatusLabel)"
        } else {
            statusMessage = "\(appState.hotkey) · \(appState.modeStatusLabel) · Control off"
        }
    }
    
    /// Custom shortcut or menu bar: toggle sticky session
    @MainActor
    func toggleDictation() async {
        await handleCustomHotkey()
    }
    
    /// Press custom hotkey once to start (sticky), again to send
    @MainActor
    private func handleCustomHotkey() async {
        if isTranscribing {
            await confirmDictation()
        } else {
            controlInput.isSticky = true
            await beginDictation(sticky: true)
        }
    }
    
    @MainActor
    func beginDictation(sticky: Bool) async {
        if isTranscribing {
            // Upgrade hold → sticky if double-tap arrives mid-session
            if sticky {
                isStickySession = true
                controlInput.isSticky = true
                statusMessage = "Sticky · ⏎ Enter to send · Esc or ✕ to cancel"
                overlayManager.setSticky(true)
            }
            return
        }
        
        isConfirming = false
        print("🎙 beginDictation sticky=\(sticky) provider=\(appState.provider.rawValue)")
        
        #if os(macOS)
        // Re-check silently. Only show the system dialog if still undetermined.
        // Never auto-open System Settings mid-dictation (user uses Enable Microphone button).
        PermissionManager.shared.refresh()
        if !AudioRecorderService.microphoneAuthorized() {
            let granted = await PermissionManager.shared.ensureMicrophoneForDictation()
            if !granted {
                lastError = "Microphone permission required"
                statusMessage = lastError ?? ""
                overlayManager.flashMessage("Allow Microphone in Settings → Privacy")
                return
            }
        }
        #endif
        
        if appState.provider.isCloud && !appState.isProviderConfigured {
            lastError = "Add your \(appState.provider.displayName) API key"
            statusMessage = lastError ?? ""
            overlayManager.flashMessage("Add API key in Settings → API")
            return
        }
        
        if appState.provider == .local && !whisperService.isModelReady {
            whisperService.ensureLocalModelReady()
            lastError = "Local model still loading"
            statusMessage = lastError ?? ""
            overlayManager.flashMessage("Local model still loading…")
            return
        }
        
        if appState.autoPaste && !clipboardService.isAccessibilityTrusted {
            _ = clipboardService.ensureAccessibilityPermissions()
        }
        
        // Remember where the cursor is *before* we show UI / steal attention
        clipboardService.captureTargetApp()
        
        isStickySession = sticky
        startRecording()
    }
    
    /// Enter / release Control / Send button
    @MainActor
    func confirmDictation() async {
        guard isTranscribing, !isConfirming else {
            print("⏎ confirmDictation ignored isTranscribing=\(isTranscribing) isConfirming=\(isConfirming)")
            return
        }
        isConfirming = true
        print("⏎ confirmDictation sticky=\(isStickySession)")
        
        // Stop session keys first so Enter doesn't re-fire mid-transcribe
        sessionKeys.stop()
        controlInput.isRecording = false
        liveAudioLevel = 0
        liveAudioBands = Array(repeating: 0, count: 24)
        statusMessage = appState.canRunAIPolish ? "Transcribing + polish…" : "Transcribing…"
        overlayManager.setProcessing()
        
        await whisperService.stopAndTranscribe(using: appState)
    }
    
    @MainActor
    private func startRecording() {
        do {
            // Keep key path live without force-recreating CGEvent taps (avoids TCC re-prompts)
            controlInput.ensureActiveForSession()
            
            try whisperService.startRecording()
            isTranscribing = true
            isConfirming = false
            lastError = nil
            liveAudioLevel = 0
            liveAudioBands = Array(repeating: 0, count: 24)
            controlInput.isSticky = isStickySession
            // Must set AFTER sticky so Enter path sees sticky session
            controlInput.isRecording = true
            
            // Dedicated Enter/Esc monitor for sticky (and hold) — critical path
            sessionKeys.start()
            
            updateStatusMessage()
            
            overlayManager.showOverlay(
                onCancel: { [weak self] in
                    Task { @MainActor in
                        await self?.cancelTranscription()
                    }
                },
                onConfirm: { [weak self] in
                    Task { @MainActor in
                        await self?.confirmDictation()
                    }
                },
                sticky: isStickySession,
                providerName: appState.provider.displayName
            )
            print("✅ Recording started sticky=\(isStickySession) — Enter should confirm")
        } catch {
            isTranscribing = false
            sessionKeys.stop()
            controlInput.isRecording = false
            controlInput.resetSessionFlags()
            lastError = error.localizedDescription
            statusMessage = error.localizedDescription
            overlayManager.flashMessage(error.localizedDescription)
            print("❌ startRecording failed: \(error)")
        }
    }
    
    /// Esc / X button — discard
    @MainActor
    func cancelTranscription() async {
        print("⎋ cancelTranscription isTranscribing=\(isTranscribing)")
        isConfirming = false
        sessionKeys.stop()
        controlInput.isRecording = false
        controlInput.resetSessionFlags()
        isStickySession = false
        liveAudioLevel = 0
        liveAudioBands = Array(repeating: 0, count: 24)
        clipboardService.clearTargetApp()
        
        if isTranscribing || whisperService.isTranscribing {
            whisperService.cancelRecording()
        }
        isTranscribing = false
        overlayManager.hideOverlay()
        lastError = nil
        statusMessage = "Cancelled"
        updateStatusMessage()
    }
    
    private func handleOutcome(_ outcome: TranscriptionOutcome) {
        DispatchQueue.main.async {
            self.sessionKeys.stop()
            self.isTranscribing = false
            self.isConfirming = false
            self.isStickySession = false
            self.controlInput.isRecording = false
            self.controlInput.resetSessionFlags()
            
            switch outcome {
            case .failure(let message, _):
                self.lastError = message
                self.statusMessage = message
                self.overlayManager.showError(message)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.overlayManager.hideOverlay()
                    self.updateStatusMessage()
                }
                
            case .success(let text, let duration):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self.lastError = "No speech detected"
                    self.statusMessage = "No speech detected"
                    self.overlayManager.showError("No speech detected")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.overlayManager.hideOverlay()
                        self.updateStatusMessage()
                    }
                    return
                }
                
                // Guard: identical completion within 2s
                let now = Date()
                if trimmed == self.lastCompletedFingerprint,
                   now.timeIntervalSince(self.lastCompletedAt) < 2.0 {
                    AppLog.debug("⏭ Ignoring duplicate transcription completion")
                    self.overlayManager.hideOverlay()
                    return
                }
                self.lastCompletedFingerprint = trimmed
                self.lastCompletedAt = now
                
                self.lastTranscript = trimmed
                self.appState.recordUsage(text: trimmed, audioSeconds: duration)
                
                let wordCount = trimmed.split { $0.isWhitespace || $0.isNewline }.count
                self.overlayManager.hideOverlay()
                
                if self.appState.autoPaste {
                    self.statusMessage = "Pasting \(wordCount) words…"
                    self.clipboardService.copyAndPaste(trimmed)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        self.statusMessage = "Pasted \(wordCount) words"
                        self.updateStatusMessage()
                    }
                } else {
                    _ = self.clipboardService.copyToClipboard(trimmed)
                    self.statusMessage = "Copied \(wordCount) words"
                    self.updateStatusMessage()
                }
            }
        }
    }
    
    func requestPermissions() {
        PermissionManager.shared.bootstrapOnce()
        PermissionManager.shared.refresh()
        controlInput.refreshAccessibility()
        controlInput.setup()
        globalHotkey.refreshAccessibilityStatus()
        globalHotkey.currentHotkey = appState.hotkey
        globalHotkey.setup()
        updateStatusMessage()
    }
}

// MARK: - Proxy for Home permission rows

@Observable
final class HotkeyStatusProxy {
    private let control: ControlDictationInput
    private let global: GlobalHotkeyService
    
    init(control: ControlDictationInput, global: GlobalHotkeyService) {
        self.control = control
        self.global = global
    }
    
    var isRegistered: Bool { control.isRegistered || global.isRegistered }
    var accessibilityTrusted: Bool { control.accessibilityTrusted || global.accessibilityTrusted }
    
    func refreshAccessibilityStatus() {
        control.refreshAccessibility()
        global.refreshAccessibilityStatus()
    }
    
    func requestAccessibilityPrompt() {
        PermissionManager.shared.requestAccessibilityFromUser()
        refreshAccessibilityStatus()
    }
}

