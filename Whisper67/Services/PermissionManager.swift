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
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        #endif
        accessibilityGranted = AXIsProcessTrusted()
        lastChecked = Date()
    }
    
    /// Call once at launch. Only requests mic if never determined; never auto-opens Accessibility prompt repeatedly.
    func bootstrapOnce() {
        refresh()
        
        #if os(macOS)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined && !defaults.bool(forKey: Keys.didPromptMicrophone) {
            defaults.set(true, forKey: Keys.didPromptMicrophone)
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.microphoneGranted = granted
                }
            }
        }
        #endif
        
        // Accessibility: prompt at most once ever, and only if not already trusted
        if !accessibilityGranted && !defaults.bool(forKey: Keys.didPromptAccessibility) {
            defaults.set(true, forKey: Keys.didPromptAccessibility)
            // Soft prompt once (system sheet). After this we only open Settings on user action.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        }
    }
    
    /// User-initiated: open Microphone privacy pane (or request if undetermined).
    func requestMicrophoneFromUser() {
        #if os(macOS)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.microphoneGranted = granted
                }
            }
        case .denied, .restricted:
            openPrivacyPane("Privacy_Microphone")
        case .authorized:
            microphoneGranted = true
        @unknown default:
            break
        }
        #endif
    }
    
    /// User-initiated: open Accessibility settings (does not spam AX prompt).
    func requestAccessibilityFromUser() {
        refresh()
        // Opening Settings is more reliable than the one-shot AX prompt for installed apps
        openPrivacyPane("Privacy_Accessibility")
        // Also try a single prompt so the app appears in the list
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        // On newer macOS, keyboard monitoring may also need Input Monitoring
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                // Don't force-open both; Accessibility is primary. User can open Input Monitoring if needed.
                _ = url
            }
        }
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
        // Prefer modern System Settings URL when available
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
    
    /// Path shown to user so they can match the Accessibility list entry.
    var appPathForDisplay: String {
        Bundle.main.bundlePath
    }
    
    var isAdHocSigned: Bool {
        // Ad-hoc signed apps lose TCC grants when the binary CDHash changes
        guard let url = Bundle.main.executableURL else { return true }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return true }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else { return true }
        // Team identifier missing ⇒ typically ad-hoc / local sign
        return info[kSecCodeInfoTeamIdentifier as String] == nil
    }
}
