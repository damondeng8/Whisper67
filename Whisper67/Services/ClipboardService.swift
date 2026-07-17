import Foundation
import AppKit
import ApplicationServices
import Observation
import Carbon.HIToolbox

/// Pastes transcription at the caret in the app the user was typing in.
@Observable
final class ClipboardService {
    static let shared = ClipboardService()
    
    private var targetBundleID: String?
    private var targetPID: pid_t = 0
    private var targetName: String = ""
    private var lastForeignBundleID: String?
    private var lastForeignPID: pid_t = 0
    private var lastForeignName: String = ""
    private var pasteGeneration = 0
    
    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bid = app.bundleIdentifier,
                  bid != Bundle.main.bundleIdentifier,
                  !app.isTerminated else { return }
            self?.lastForeignBundleID = bid
            self?.lastForeignPID = app.processIdentifier
            self?.lastForeignName = app.localizedName ?? bid
        }
        
        if let front = NSWorkspace.shared.frontmostApplication,
           let bid = front.bundleIdentifier,
           bid != Bundle.main.bundleIdentifier {
            lastForeignBundleID = bid
            lastForeignPID = front.processIdentifier
            lastForeignName = front.localizedName ?? bid
        }
    }
    
    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }
    
    // MARK: - Capture target when dictation starts
    
    func captureTargetApp() {
        let our = Bundle.main.bundleIdentifier
        let front = NSWorkspace.shared.frontmostApplication
        
        if let front, let bid = front.bundleIdentifier, bid != our, !front.isTerminated {
            targetBundleID = bid
            targetPID = front.processIdentifier
            targetName = front.localizedName ?? bid
            lastForeignBundleID = bid
            lastForeignPID = targetPID
            lastForeignName = targetName
        } else if let bid = lastForeignBundleID, lastForeignPID != 0 {
            targetBundleID = bid
            targetPID = lastForeignPID
            targetName = lastForeignName
        } else {
            targetBundleID = nil
            targetPID = 0
            targetName = ""
        }
        print("🎯 Paste target: \(targetName) pid=\(targetPID) \(targetBundleID ?? "")")
    }
    
    func clearTargetApp() {
        targetBundleID = nil
        targetPID = 0
        targetName = ""
    }
    
    // MARK: - Clipboard
    
    @discardableResult
    func copyToClipboard(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        pb.prepareForNewContents(with: [])
        pb.clearContents()
        let declared = pb.declareTypes([.string], owner: nil)
        let ok = pb.setString(text, forType: .string)
        print("📋 Clipboard types=\(declared) set=\(ok) len=\(text.count)")
        return ok
    }
    
    // MARK: - Public paste
    
    func copyAndPaste(_ text: String) {
        guard !text.isEmpty else { return }
        pasteGeneration += 1
        let gen = pasteGeneration
        
        guard copyToClipboard(text) else {
            print("❌ clipboard write failed")
            return
        }
        
        // Hide our UI so we don't receive Cmd+V
        for w in NSApp.windows {
            if w is TranscriptionOverlayWindow {
                w.orderOut(nil)
                continue
            }
            if w.isVisible && (w.canBecomeMain || w.canBecomeKey) {
                w.orderOut(nil)
            }
        }
        
        let pid = targetPID != 0 ? targetPID : lastForeignPID
        let name = targetName.isEmpty ? lastForeignName : targetName
        let bid = targetBundleID ?? lastForeignBundleID
        
        print("🎯 Auto-paste gen=\(gen) → \(name) pid=\(pid)")
        
        // Fast path: activate + paste on next runloop tick (no stacked delays)
        DispatchQueue.main.async { [weak self] in
            self?.runPasteFast(text: text, pid: pid, bundleID: bid, name: name, generation: gen)
        }
    }
    
    /// Single-pass paste: AX first (no focus dance needed when trusted), else activate + Cmd+V.
    /// One short fallback only if both miss — avoids multi-second retry chains.
    private func runPasteFast(text: String, pid: pid_t, bundleID: String?, name: String, generation: Int) {
        guard generation == pasteGeneration else { return }
        _ = copyToClipboard(text)
        
        // Prefer AX insert immediately — works without activating when focus is already correct
        if insertViaAX(text) {
            print("✅ Paste via AX (fast)")
            return
        }
        
        activate(pid: pid, bundleID: bundleID)
        
        // Brief yield for app activation (~40ms), then Cmd+V once
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self, generation == self.pasteGeneration else { return }
            self.activate(pid: pid, bundleID: bundleID)
            
            if self.insertViaAX(text) {
                print("✅ Paste via AX after activate")
                return
            }
            
            self.postCommandV()
            print("✅ Paste via CGEvent Cmd+V")
            
            // System Events only when Accessibility is off (Cmd+V alone is often blocked)
            if !AXIsProcessTrusted() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    guard let self, generation == self.pasteGeneration else { return }
                    if pid > 0 {
                        _ = self.osascriptPaste(pid: pid)
                    } else {
                        _ = self.osascriptPasteFront()
                    }
                }
            }
        }
    }
    
    private func activate(pid: pid_t, bundleID: String?) {
        if pid > 0, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
            print("🎯 activate pid \(pid) \(app.localizedName ?? "")")
            return
        }
        if let bundleID,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
            print("🎯 activate bundle \(bundleID)")
            return
        }
        print("⚠️ activate: no target")
    }
    
    // MARK: - AX insert
    
    private func insertViaAX(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard err == .success, let focused else { return false }
        
        let el = focused as! AXUIElement
        
        if AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
            return true
        }
        
        var val: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &val) == .success,
           let existing = val as? String {
            var range = CFRange(location: existing.utf16.count, length: 0)
            var rangeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
               let rangeRef {
                let ax = unsafeBitCast(rangeRef, to: AXValue.self)
                _ = AXValueGetValue(ax, .cfRange, &range)
            }
            let ns = existing as NSString
            let loc = min(max(0, range.location), ns.length)
            let len = min(max(0, range.length), ns.length - loc)
            let updated = ns.replacingCharacters(in: NSRange(location: loc, length: len), with: text)
            if AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, updated as CFTypeRef) == .success {
                return true
            }
        }
        return false
    }
    
    // MARK: - Cmd+V via CGEvent
    
    private func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0
        
        let keyV = CGKeyCode(kVK_ANSI_V)
        
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else {
            print("❌ CGEvent create failed")
            return
        }
        
        down.flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue)
        up.flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue)
        
        down.post(tap: .cghidEventTap)
        usleep(8_000)
        up.post(tap: .cghidEventTap)
    }
    
    // MARK: - osascript fallback
    
    private func osascriptPaste(pid: pid_t) -> Bool {
        let source = """
        tell application "System Events"
          set frontmost of first process whose unix id is \(pid) to true
          delay 0.04
          keystroke "v" using command down
        end tell
        """
        return runOSAscript(source)
    }
    
    private func osascriptPasteFront() -> Bool {
        let source = """
        tell application "System Events"
          delay 0.02
          keystroke "v" using command down
        end tell
        """
        return runOSAscript(source)
    }
    
    private func runOSAscript(_ source: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let err = Pipe()
        p.standardError = err
        do {
            try p.run()
            p.waitUntilExit()
            let ok = p.terminationStatus == 0
            if !ok {
                let data = err.fileHandleForReading.readDataToEndOfFile()
                print("osascript err: \(String(data: data, encoding: .utf8) ?? "")")
            }
            return ok
        } catch {
            print("osascript failed: \(error)")
            return false
        }
    }
    
    func ensureAccessibilityPermissions() -> Bool { AXIsProcessTrusted() }
    
    func testPasteFunction() {
        captureTargetApp()
        copyAndPaste("Whisper67 paste OK \(Date())")
    }
}
