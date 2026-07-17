import Foundation
import AppKit
import Carbon
import ApplicationServices
import Observation

/// Global dictate hotkey using both Carbon Event HotKeys and NSEvent monitors.
/// Carbon alone is unreliable in pure SwiftUI apps; monitors need Accessibility.
@Observable
final class GlobalHotkeyService {
    static let shared = GlobalHotkeyService()
    
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastFire: Date = .distantPast
    private let debounce: TimeInterval = 0.35
    
    var onHotkeyPressed: (() -> Void)?
    var isRegistered = false
    var lastError: String?
    var accessibilityTrusted = false
    
    /// Display string, e.g. "⌥Space"
    var currentHotkey: String = "⌥Space" {
        didSet {
            if currentHotkey != oldValue {
                updateGlobalHotkey()
            }
        }
    }
    
    private init() {}
    
    private var didAddObservers = false
    
    func setup() {
        refreshAccessibilityStatus()
        updateGlobalHotkey()
        
        guard !didAddObservers else { return }
        didAddObservers = true
        
        // Re-register when focus changes so Carbon/global hotkeys stay live in background
        for name in [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
            NSApplication.didFinishLaunchingNotification
        ] {
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshAccessibilityStatus()
                // Always re-assert registration in background agent mode
                self?.updateGlobalHotkey()
            }
        }
    }
    
    func refreshAccessibilityStatus() {
        accessibilityTrusted = AXIsProcessTrusted()
    }
    
    func requestAccessibilityPrompt() {
        // User-initiated only — open Settings via PermissionManager path if available
        PermissionManager.shared.requestAccessibilityFromUser()
        refreshAccessibilityStatus()
    }
    
    private func updateGlobalHotkey() {
        unregisterHotkey()
        registerHotkey()
    }
    
    private func registerHotkey() {
        guard !currentHotkey.isEmpty else { return }
        let (keyCode, carbonModifiers, nsFlags) = parseHotkey(currentHotkey)
        guard keyCode != 0 else {
            lastError = "Could not parse hotkey \(currentHotkey)"
            isRegistered = false
            return
        }
        
        // 1) Carbon hotkey (works system-wide without polling)
        var hotkeyID = EventHotKeyID(signature: OSType(0x57363731), id: 1) // 'W671'
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(carbonModifiers),
            hotkeyID,
            GetEventDispatcherTarget(),
            0,
            &hotkeyRef
        )
        
        if status == noErr {
            // Install handler only once
            if eventHandler == nil {
                InstallEventHandler(
                    GetEventDispatcherTarget(),
                    { _, _, userData -> OSStatus in
                        guard let userData else { return noErr }
                        let service = Unmanaged<GlobalHotkeyService>.fromOpaque(userData).takeUnretainedValue()
                        service.fire()
                        return noErr
                    },
                    1,
                    &eventType,
                    Unmanaged.passUnretained(self).toOpaque(),
                    &eventHandler
                )
            }
            print("✅ Carbon hotkey registered: \(currentHotkey) keyCode=\(keyCode) mods=\(carbonModifiers)")
        } else {
            print("⚠️ Carbon RegisterEventHotKey failed: \(status) — falling back to NSEvent monitors")
            lastError = "Hotkey register status \(status)"
        }
        
        // 2) NSEvent monitors as backup (needs Accessibility for global)
        refreshAccessibilityStatus()
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.matches(event, keyCode: keyCode, flags: nsFlags) {
                self.fire()
                return nil // consume
            }
            return event
        }
        
        if accessibilityTrusted {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return }
                if self.matches(event, keyCode: keyCode, flags: nsFlags) {
                    self.fire()
                }
            }
            print("✅ Global NSEvent monitor installed for \(currentHotkey)")
        } else {
            print("⚠️ Accessibility not trusted — global monitor unavailable (local still works in-app)")
            // Do not auto-prompt; user enables via Settings button
        }
        
        // Carbon success is enough for system-wide hotkeys even without NSEvent global
        isRegistered = (status == noErr) || (localMonitor != nil)
        if isRegistered { lastError = nil }
    }
    
    private func unregisterHotkey() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
        // Keep Carbon event handler installed (signature is stable)
        
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isRegistered = false
    }
    
    private func matches(_ event: NSEvent, keyCode: Int, flags: NSEvent.ModifierFlags) -> Bool {
        guard event.keyCode == UInt16(keyCode) else { return false }
        // Compare relevant modifier bits only
        let relevant: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let eventMods = event.modifierFlags.intersection(relevant)
        return eventMods == flags
    }
    
    private func fire() {
        let now = Date()
        guard now.timeIntervalSince(lastFire) >= debounce else { return }
        lastFire = now
        print("🎯 Hotkey fired: \(currentHotkey)")
        DispatchQueue.main.async {
            self.onHotkeyPressed?()
        }
    }
    
    /// Returns (carbonKeyCode, carbonModifiers, nsEventFlags)
    private func parseHotkey(_ hotkey: String) -> (Int, Int, NSEvent.ModifierFlags) {
        var carbonMods = 0
        var nsFlags: NSEvent.ModifierFlags = []
        
        if hotkey.contains("⌃") {
            carbonMods |= controlKey
            nsFlags.insert(.control)
        }
        if hotkey.contains("⌥") {
            carbonMods |= optionKey
            nsFlags.insert(.option)
        }
        if hotkey.contains("⇧") {
            carbonMods |= shiftKey
            nsFlags.insert(.shift)
        }
        if hotkey.contains("⌘") {
            carbonMods |= cmdKey
            nsFlags.insert(.command)
        }
        
        let mainKey = hotkey
            .replacingOccurrences(of: "⌃", with: "")
            .replacingOccurrences(of: "⌥", with: "")
            .replacingOccurrences(of: "⇧", with: "")
            .replacingOccurrences(of: "⌘", with: "")
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
        
        let keyCode = keyCodeForString(mainKey)
        return (keyCode, carbonMods, nsFlags)
    }
    
    private func keyCodeForString(_ key: String) -> Int {
        switch key {
        case "SPACE": return kVK_Space
        case "A": return kVK_ANSI_A
        case "B": return kVK_ANSI_B
        case "C": return kVK_ANSI_C
        case "D": return kVK_ANSI_D
        case "E": return kVK_ANSI_E
        case "F": return kVK_ANSI_F
        case "G": return kVK_ANSI_G
        case "H": return kVK_ANSI_H
        case "I": return kVK_ANSI_I
        case "J": return kVK_ANSI_J
        case "K": return kVK_ANSI_K
        case "L": return kVK_ANSI_L
        case "M": return kVK_ANSI_M
        case "N": return kVK_ANSI_N
        case "O": return kVK_ANSI_O
        case "P": return kVK_ANSI_P
        case "Q": return kVK_ANSI_Q
        case "R": return kVK_ANSI_R
        case "S": return kVK_ANSI_S
        case "T": return kVK_ANSI_T
        case "U": return kVK_ANSI_U
        case "V": return kVK_ANSI_V
        case "W": return kVK_ANSI_W
        case "X": return kVK_ANSI_X
        case "Y": return kVK_ANSI_Y
        case "Z": return kVK_ANSI_Z
        case "0": return kVK_ANSI_0
        case "1": return kVK_ANSI_1
        case "2": return kVK_ANSI_2
        case "3": return kVK_ANSI_3
        case "4": return kVK_ANSI_4
        case "5": return kVK_ANSI_5
        case "6": return kVK_ANSI_6
        case "7": return kVK_ANSI_7
        case "8": return kVK_ANSI_8
        case "9": return kVK_ANSI_9
        case "F1": return kVK_F1
        case "F2": return kVK_F2
        case "F3": return kVK_F3
        case "F4": return kVK_F4
        case "F5": return kVK_F5
        case "F6": return kVK_F6
        case "F7": return kVK_F7
        case "F8": return kVK_F8
        case "F9": return kVK_F9
        case "F10": return kVK_F10
        case "F11": return kVK_F11
        case "F12": return kVK_F12
        case "RETURN", "ENTER": return kVK_Return
        case "TAB": return kVK_Tab
        case "DELETE": return kVK_Delete
        case "ESCAPE", "ESC": return kVK_Escape
        default: return kVK_Space
        }
    }
    
    deinit {
        unregisterHotkey()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
