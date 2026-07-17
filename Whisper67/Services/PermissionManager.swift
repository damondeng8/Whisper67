import Foundation
import AppKit
import AVFoundation
import ApplicationServices
import Observation

/// Central permission state — never spam-prompts. User clicks to request.
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
    }
    
    private init() {
        refresh()
    }
    
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
    
    /// Call once at launch. Only requests mic if never determined.
    func bootstrapOnce() {
        refresh()
        
        #if os(macOS)
        if !microphoneGranted {
            let undetermined: Bool
            if #available(macOS 14.0, *) {
                undetermined = AVAudioApplication.shared.recordPermission == .undetermined
            } else {
                undetermined = AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
            }
            if undetermined && !defaults.bool(forKey: Keys.didPromptMicrophone) {
                defaults.set(true, forKey: Keys.didPromptMicrophone)
                Task { @MainActor in
                    let granted = await AudioRecorderService.requestMicrophoneAccess()
                    self.microphoneGranted = granted
                    self.microphoneStatusText = Self.describeMicStatus()
                    print("🎤 Bootstrap mic permission: \(granted)")
                }
            }
        }
        #endif
        
        if !accessibilityGranted && !defaults.bool(forKey: Keys.didPromptAccessibility) {
            defaults.set(true, forKey: Keys.didPromptAccessibility)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        }
    }
    
    /// User-initiated: request or open Microphone privacy pane.
    func requestMicrophoneFromUser() {
        #if os(macOS)
        refresh()
        if microphoneGranted {
            print("🎤 Mic already granted")
            return
        }
        
        let undetermined: Bool
        if #available(macOS 14.0, *) {
            undetermined = AVAudioApplication.shared.recordPermission == .undetermined
        } else {
            undetermined = AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
        }
        
        if undetermined {
            Task { @MainActor in
                let granted = await AudioRecorderService.requestMicrophoneAccess()
                self.microphoneGranted = granted
                self.microphoneStatusText = Self.describeMicStatus()
                print("🎤 User mic request: \(granted)")
                if !granted {
                    self.openPrivacyPane("Privacy_Microphone")
                }
            }
        } else {
            // Denied / restricted — open Settings so user can re-enable
            openPrivacyPane("Privacy_Microphone")
        }
        #endif
    }
    
    func requestAccessibilityFromUser() {
        refresh()
        openPrivacyPane("Privacy_Accessibility")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    func openInputMonitoringSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
        ]
        for s in urls {
            if let url = URL(string: s) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }
    
    func openPrivacyPane(_ anchor: String) {
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
