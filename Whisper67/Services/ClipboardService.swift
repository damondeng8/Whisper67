import Foundation
import AppKit
import ApplicationServices
import Observation
import Carbon.HIToolbox

/// Copies transcription to the clipboard and pastes at the caret in the target app.
///
/// Always leaves the text **on the clipboard** so History + manual Cmd+V still work
/// if synthetic paste fails. Never restores a previous clipboard over dictation text.
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
    private var pasteInFlight = false
    
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
        AppLog.debug("🎯 Paste target: \(targetName) pid=\(targetPID) \(targetBundleID ?? "")")
    }
    
    func clearTargetApp() {
        targetBundleID = nil
        targetPID = 0
        targetName = ""
    }
    
    // MARK: - Clipboard
    
    /// Always leave dictation text on the pasteboard (user can Cmd+V if auto-paste misses).
    @discardableResult
    func copyToClipboard(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        // writeObjects is more reliable across apps than setString alone
        let ok = pb.writeObjects([text as NSString])
        if !ok {
            pb.declareTypes([.string], owner: nil)
            _ = pb.setString(text, forType: .string)
        }
        // Verify
        let readBack = pb.string(forType: .string) ?? ""
        let success = readBack == text
        AppLog.debug("📋 Clipboard set=\(success) len=\(text.count) read=\(readBack.count)")
        return success || ok
    }
    
    // MARK: - Public paste
    
    func copyAndPaste(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Always put text on clipboard first — even if a prior paste is still finishing
        guard copyToClipboard(text) else {
            AppLog.info("❌ clipboard write failed")
            return
        }
        
        pasteGeneration += 1
        let gen = pasteGeneration
        pasteInFlight = true
        
        for w in NSApp.windows where w is TranscriptionOverlayWindow {
            w.orderOut(nil)
        }
        
        resolveTargetIfNeeded()
        
        let pid = targetPID != 0 ? targetPID : lastForeignPID
        let name = targetName.isEmpty ? lastForeignName : targetName
        let bid = targetBundleID ?? lastForeignBundleID
        
        AppLog.debug("🎯 Auto-paste gen=\(gen) → \(name) pid=\(pid) AX=\(AXIsProcessTrusted())")
        
        DispatchQueue.main.async { [weak self] in
            self?.runPastePipeline(text: text, pid: pid, bundleID: bid, generation: gen)
        }
    }
    
    private func runPastePipeline(text: String, pid: pid_t, bundleID: String?, generation: Int) {
        guard generation == pasteGeneration else {
            finishPaste(generation: generation)
            return
        }
        
        _ = copyToClipboard(text)
        activate(pid: pid, bundleID: bundleID)
        
        waitUntilFrontmost(pid: pid, bundleID: bundleID, generation: generation, attemptsLeft: 20) { [weak self] activated in
            guard let self else { return }
            guard generation == self.pasteGeneration else {
                self.finishPaste(generation: generation)
                return
            }
            
            if !activated {
                AppLog.debug("⚠️ Target never became frontmost — pasting to current frontmost")
            }
            
            // Give the key window a beat to become first responder
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, generation == self.pasteGeneration else {
                    self?.finishPaste(generation: generation)
                    return
                }
                
                if self.looksLikeFrontIsOurs() {
                    self.activate(pid: pid, bundleID: bundleID)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                        self?.firePaste(text: text, pid: pid, generation: generation)
                    }
                } else {
                    self.firePaste(text: text, pid: pid, generation: generation)
                }
            }
        }
    }
    
    private func firePaste(text: String, pid: pid_t, generation: Int) {
        guard generation == pasteGeneration else {
            finishPaste(generation: generation)
            return
        }
        
        // Re-assert clipboard right before paste (some apps steal focus + clipboard)
        _ = copyToClipboard(text)
        
        // 1) Prefer AX insert into focused field of target (no keystroke needed)
        if insertViaAXSelectedText(text, preferredPID: pid > 0 ? pid : nil) {
            AppLog.debug("✅ Paste via AX selectedText")
            finishPaste(generation: generation)
            return
        }
        
        // 2) Synthetic ⌘V (requires Accessibility for most hosts)
        postCommandVOnce()
        AppLog.debug("✅ Paste via CGEvent Cmd+V")
        
        // 3) If still not trusted, System Events once
        if !AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, generation == self.pasteGeneration else {
                    self?.finishPaste(generation: generation)
                    return
                }
                if pid > 0 {
                    _ = self.osascriptPaste(pid: pid)
                } else {
                    _ = self.osascriptPasteFront()
                }
                AppLog.debug("↩️ Paste via System Events")
                // Keep text on clipboard — do not restore previous
                self.finishPaste(generation: generation)
            }
            return
        }
        
        // Leave dictated text on clipboard for manual Cmd+V if synthetic paste missed
        finishPaste(generation: generation)
    }
    
    private func finishPaste(generation: Int) {
        if generation == pasteGeneration {
            pasteInFlight = false
        }
    }
    
    // MARK: - Target resolution
    
    private func resolveTargetIfNeeded() {
        let our = Bundle.main.bundleIdentifier
        if targetPID == 0 {
            if let front = NSWorkspace.shared.frontmostApplication,
               let bid = front.bundleIdentifier,
               bid != our, !front.isTerminated {
                targetBundleID = bid
                targetPID = front.processIdentifier
                targetName = front.localizedName ?? bid
            } else if lastForeignPID != 0 {
                targetPID = lastForeignPID
                targetBundleID = lastForeignBundleID
                targetName = lastForeignName
            }
        }
    }
    
    private func looksLikeFrontIsOurs() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
    }
    
    // MARK: - Activate + wait
    
    private func activate(pid: pid_t, bundleID: String?) {
        if pid > 0, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
            activateApp(app)
            AppLog.debug("🎯 activate pid \(pid) \(app.localizedName ?? "")")
            return
        }
        if let bundleID,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { !$0.isTerminated }) {
            activateApp(app)
            AppLog.debug("🎯 activate bundle \(bundleID)")
            return
        }
        AppLog.debug("⚠️ activate: no target")
    }
    
    private func activateApp(_ app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        // Ignoring-other-apps is required so we leave Whisper67
        app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    }
    
    private func waitUntilFrontmost(
        pid: pid_t,
        bundleID: String?,
        generation: Int,
        attemptsLeft: Int,
        completion: @escaping (Bool) -> Void
    ) {
        guard generation == pasteGeneration else {
            finishPaste(generation: generation)
            return
        }
        
        if isFrontmost(pid: pid, bundleID: bundleID) {
            completion(true)
            return
        }
        
        if attemptsLeft <= 0 {
            activate(pid: pid, bundleID: bundleID)
            completion(false)
            return
        }
        
        if attemptsLeft % 5 == 0 {
            activate(pid: pid, bundleID: bundleID)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.waitUntilFrontmost(
                pid: pid,
                bundleID: bundleID,
                generation: generation,
                attemptsLeft: attemptsLeft - 1,
                completion: completion
            )
        }
    }
    
    private func isFrontmost(pid: pid_t, bundleID: String?) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        if pid > 0, front.processIdentifier == pid { return true }
        if let bundleID, front.bundleIdentifier == bundleID { return true }
        return false
    }
    
    // MARK: - AX insert (selected text only)
    
    private func insertViaAXSelectedText(_ text: String, preferredPID: pid_t?) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        
        if let pid = preferredPID, pid > 0 {
            let appEl = AXUIElementCreateApplication(pid)
            var focused: CFTypeRef?
            if AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
               let focused {
                let el = focused as! AXUIElement
                if setSelectedText(el, text: text) { return true }
            }
        }
        
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return false }
        let el = focused as! AXUIElement
        var pid: pid_t = 0
        if AXUIElementGetPid(el, &pid) == .success,
           pid == ProcessInfo.processInfo.processIdentifier {
            return false // don't paste into ourselves
        }
        return setSelectedText(el, text: text)
    }
    
    private func setSelectedText(_ el: AXUIElement, text: String) -> Bool {
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(el, kAXSelectedTextAttribute as CFString, &settable) == .success,
           !settable.boolValue {
            return false
        }
        return AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }
    
    // MARK: - Cmd+V
    
    private func postCommandVOnce() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0
        
        let keyV = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else {
            AppLog.info("❌ CGEvent create failed")
            return
        }
        
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        usleep(8_000)
        up.post(tap: .cghidEventTap)
    }
    
    // MARK: - osascript
    
    private func osascriptPaste(pid: pid_t) -> Bool {
        let source = """
        tell application "System Events"
          set frontmost of first process whose unix id is \(pid) to true
          delay 0.08
          keystroke "v" using command down
        end tell
        """
        return runOSAscript(source)
    }
    
    private func osascriptPasteFront() -> Bool {
        let source = """
        tell application "System Events"
          delay 0.05
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
            return p.terminationStatus == 0
        } catch {
            AppLog.info("osascript failed: \(error)")
            return false
        }
    }
    
    func ensureAccessibilityPermissions() -> Bool { AXIsProcessTrusted() }
    
    func testPasteFunction() {
        captureTargetApp()
        copyAndPaste("Whisper67 paste OK \(Date())")
    }
}
