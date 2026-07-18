import Foundation
import AppKit
import AVFoundation
import ApplicationServices
import Observation

/// Central permission state — never spam-prompts.
/// System dialogs only when status is undetermined (first time) or the user explicitly clicks.
@Observable
final class PermissionManager {
    static let shared = PermissionManager()
    
    var microphoneGranted = false
    var accessibilityGranted = false
    private(set) var lastChecked = Date()
    /// Human-readable mic status for UI/debug
    private(set) var microphoneStatusText = "Unknown"
    
    private let defaults = UserDefaults.standard
    private enum Keys {
        static let didPromptAccessibility = "whisper67.didPromptAccessibility"
        static let didPromptMicrophone = "whisper67.didPromptMicrophone"
        static let didOpenMicSettings = "whisper67.didOpenMicSettings"
        static let didOpenAXSettings = "whisper67.didOpenAXSettings"
    }
    
    /// In-process: last time we opened a privacy pane (throttle Settings spam)
    private var lastPrivacyPaneOpen: [String: Date] = [:]
    private let privacyPaneCooldown: TimeInterval = 45
    
    /// True after launch bootstrap finished — guards against double bootstrap
    private var didBootstrap = false
    
    private init() {
        refresh()
    }
    
    // MARK: - Silent checks
    
    /// Silent check — never shows a system dialog.
    func refresh() {
        #if os(macOS)
        microphoneGranted = AudioRecorderService.microphoneAuthorized()
        microphoneStatusText = Self.describeMicStatus()
        #endif
        accessibilityGranted = AXIsProcessTrusted()
        lastChecked = Date()
    }
    
    private static func describeMicStatus() -> String {
        #if os(macOS)
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return "Granted"
            case .denied: return "Denied"
            case .undetermined: return "Not determined"
            @unknown default: break
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "Granted"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not determined"
        @unknown default: return "Unknown"
        }
        #else
        return "Unknown"
        #endif
    }
    
    var isMicrophoneUndetermined: Bool {
        #if os(macOS)
        if #available(macOS 14.0, *) {
            if AVAudioApplication.shared.recordPermission == .undetermined { return true }
        }
        return AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
        #else
        return false
        #endif
    }
    
    // MARK: - Launch (once, non-spammy)
    
    /// Call once at launch. At most one first-run mic dialog if never asked.
    /// Never auto-opens System Settings. Never re-prompts Accessibility after first ask.
    func bootstrapOnce() {
        guard !didBootstrap else {
            refresh()
            return
        }
        didBootstrap = true
        refresh()
        
        #if os(macOS)
        // Mic: only if never determined and we have not already shown the dialog this install
        if !microphoneGranted && isMicrophoneUndetermined && !defaults.bool(forKey: Keys.didPromptMicrophone) {
            defaults.set(true, forKey: Keys.didPromptMicrophone)
            Task { @MainActor in
                let granted = await AudioRecorderService.requestMicrophoneAccess()
                self.microphoneGranted = granted
                self.microphoneStatusText = Self.describeMicStatus()
                print("🎤 Bootstrap mic permission: \(granted)")
            }
        }
        #endif
        
        // Accessibility: silent check only — never auto-prompt or open Settings on launch.
        // User enables via Home / Shortcuts / menu "Fix Permissions" when ready.
        accessibilityGranted = AXIsProcessTrusted()
        if accessibilityGranted {
            defaults.set(true, forKey: Keys.didPromptAccessibility)
        }
    }
    
    // MARK: - User-initiated (buttons)
    
    /// User-initiated: request mic if undetermined, else open Settings (throttled).
    func requestMicrophoneFromUser(forceOpenSettings: Bool = true) {
        #if os(macOS)
        refresh()
        if microphoneGranted {
            print("🎤 Mic already granted")
            return
        }
        
        if isMicrophoneUndetermined {
            defaults.set(true, forKey: Keys.didPromptMicrophone)
            Task { @MainActor in
                let granted = await AudioRecorderService.requestMicrophoneAccess()
                self.microphoneGranted = granted
                self.microphoneStatusText = Self.describeMicStatus()
                print("🎤 User mic request: \(granted)")
                // Only open Settings if denied after explicit user click
                if !granted && forceOpenSettings {
                    self.openPrivacyPane("Privacy_Microphone", force: true)
                }
            }
        } else if forceOpenSettings {
            // Denied / restricted — open Settings so user can re-enable
            openPrivacyPane("Privacy_Microphone", force: true)
        }
        #endif
    }
    
    /// Request mic only when undetermined — never opens Settings. Safe for dictation start.
    @MainActor
    func ensureMicrophoneForDictation() async -> Bool {
        refresh()
        if microphoneGranted || AudioRecorderService.microphoneAuthorized() {
            return true
        }
        guard isMicrophoneUndetermined else {
            // Already denied — do not re-dialog or open Settings mid-flow
            return false
        }
        defaults.set(true, forKey: Keys.didPromptMicrophone)
        let granted = await AudioRecorderService.requestMicrophoneAccess()
        microphoneGranted = granted
        microphoneStatusText = Self.describeMicStatus()
        return granted
    }
    
    /// User-initiated Accessibility enable.
    /// Opens Settings (throttled). System AX prompt at most once per install.
    func requestAccessibilityFromUser() {
        refresh()
        if accessibilityGranted {
            print("♿ Accessibility already granted")
            return
        }
        
        // First user click: allow the official system prompt once
        if !defaults.bool(forKey: Keys.didPromptAccessibility) {
            defaults.set(true, forKey: Keys.didPromptAccessibility)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            accessibilityGranted = AXIsProcessTrustedWithOptions(options)
            if accessibilityGranted { return }
        }
        
        // Subsequent clicks: just open Settings (no second system dialog)
        openPrivacyPane("Privacy_Accessibility", force: true)
    }
    
    func openInputMonitoringSettings() {
        openPrivacyPane("Privacy_ListenEvent", force: true)
    }
    
    /// Open a privacy pane. `force` bypasses cooldown (use for explicit button presses).
    func openPrivacyPane(_ anchor: String, force: Bool = false) {
        if !force {
            if let last = lastPrivacyPaneOpen[anchor],
               Date().timeIntervalSince(last) < privacyPaneCooldown {
                return
            }
        }
        lastPrivacyPaneOpen[anchor] = Date()
        
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)"
        ]
        for s in urls {
            if let url = URL(string: s) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }
    
    var appPathForDisplay: String {
        Bundle.main.bundlePath
    }
    
    var isAdHocSigned: Bool {
        guard let url = Bundle.main.executableURL else { return true }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return true }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else { return true }
        return info[kSecCodeInfoTeamIdentifier as String] == nil
    }
}
