import Foundation
import AppKit
import ApplicationServices
import Observation
import Carbon.HIToolbox

/// Pastes transcription at the caret in the app the user was typing in.
///
/// **Exactly one** Cmd+V per dictation — dual posts (HID + postToPid) caused
/// double inserts ("Yo what's up…" twice).
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
    
    /// Blocks overlapping paste pipelines (completion handler races, double confirm).
    private var pasteInFlight = false
    private var lastPasteFingerprint: String = ""
    private var lastPasteAt: Date = .distantPast
    
    private var previousClipboard: String?
    
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
    func copyToClipboard(_ text: String, rememberPrevious: Bool = true) -> Bool {
        let pb = NSPasteboard.general
        if rememberPrevious {
            previousClipboard = pb.string(forType: .string)
        }
        pb.clearContents()
        let ok = pb.setString(text, forType: .string)
        pb.setString(text, forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
        print("📋 Clipboard set=\(ok) len=\(text.count)")
        return ok
    }
    
    // MARK: - Public paste
    
    func copyAndPaste(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Debounce: same text within 1.2s, or any paste still running
        let now = Date()
        if pasteInFlight {
            print("⏭ Paste skipped — already in flight")
            return
        }
        if text == lastPasteFingerprint, now.timeIntervalSince(lastPasteAt) < 1.2 {
            print("⏭ Paste skipped — duplicate within 1.2s")
            return
        }
        
        pasteGeneration += 1
        let gen = pasteGeneration
        pasteInFlight = true
        lastPasteFingerprint = text
        lastPasteAt = now
        
        guard copyToClipboard(text, rememberPrevious: true) else {
            print("❌ clipboard write failed")
            pasteInFlight = false
            return
        }
        
        for w in NSApp.windows where w is TranscriptionOverlayWindow {
            w.orderOut(nil)
        }
        
        resolveTargetIfNeeded()
        
        let pid = targetPID != 0 ? targetPID : lastForeignPID
        let name = targetName.isEmpty ? lastForeignName : targetName
        let bid = targetBundleID ?? lastForeignBundleID
        
        print("🎯 Auto-paste gen=\(gen) → \(name) pid=\(pid) AX=\(AXIsProcessTrusted())")
        
        DispatchQueue.main.async { [weak self] in
            self?.runPastePipeline(text: text, pid: pid, bundleID: bid, generation: gen)
        }
    }
    
    private func runPastePipeline(text: String, pid: pid_t, bundleID: String?, generation: Int) {
        guard generation == pasteGeneration else {
            finishPaste(generation: generation)
            return
        }
        
        // Re-assert clipboard without clobbering previousClipboard snapshot
        _ = copyToClipboard(text, rememberPrevious: false)
        
        activate(pid: pid, bundleID: bundleID)
        
        waitUntilFrontmost(pid: pid, bundleID: bundleID, generation: generation, attemptsLeft: 12) { [weak self] activated in
            guard let self, generation == self.pasteGeneration else {
                self?.finishPaste(generation: generation)
                return
            }
            
            if !activated {
                print("⚠️ Target never became frontmost — pasting to current frontmost")
            }
            
            // One settle frame for key window, then a single Cmd+V
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                guard let self, generation == self.pasteGeneration else {
                    self?.finishPaste(generation: generation)
                    return
                }
                
                // If we still own focus, one more activate then paste once
                if self.looksLikeFrontIsOurs() {
                    self.activate(pid: pid, bundleID: bundleID)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        guard let self, generation == self.pasteGeneration else {
                            self?.finishPaste(generation: generation)
                            return
                        }
                        self.fireSinglePaste(text: text, pid: pid, generation: generation)
                    }
                } else {
                    self.fireSinglePaste(text: text, pid: pid, generation: generation)
                }
            }
        }
    }
    
    /// Exactly one synthetic ⌘V. No HID+pid dual post, no automatic second paste.
    private func fireSinglePaste(text: String, pid: pid_t, generation: Int) {
        guard generation == pasteGeneration else {
            finishPaste(generation: generation)
            return
        }
        
        _ = copyToClipboard(text, rememberPrevious: false)
        
        if !AXIsProcessTrusted() {
            // Without Accessibility, CGEvent is often ignored — use System Events once
            if pid > 0 {
                _ = osascriptPaste(pid: pid)
            } else {
                _ = osascriptPasteFront()
            }
            print("✅ Paste via System Events (single)")
        } else {
            postCommandVOnce()
            print("✅ Paste via CGEvent Cmd+V (single)")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            self?.restorePreviousClipboardIfSafe(pasted: text)
            self?.finishPaste(generation: generation)
        }
    }
    
    private func finishPaste(generation: Int) {
        // Only clear in-flight if this is still the active generation
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
            print("🎯 activate pid \(pid) \(app.localizedName ?? "")")
            return
        }
        if let bundleID,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { !$0.isTerminated }) {
            activateApp(app)
            print("🎯 activate bundle \(bundleID)")
            return
        }
        print("⚠️ activate: no target")
    }
    
    private func activateApp(_ app: NSRunningApplication) {
        app.activate(options: [.activateIgnoringOtherApps])
        if app.isHidden {
            app.unhide()
        }
    }
    
    private func waitUntilFrontmost(
        pid: pid_t,
        bundleID: String?,
        generation: Int,
        attemptsLeft: Int,
        completion: @escaping (Bool) -> Void
    ) {
        guard generation == pasteGeneration else { return }
        
        if isFrontmost(pid: pid, bundleID: bundleID) {
            completion(true)
            return
        }
        
        if attemptsLeft <= 0 {
            activate(pid: pid, bundleID: bundleID)
            completion(false)
            return
        }
        
        if attemptsLeft % 4 == 0 {
            activate(pid: pid, bundleID: bundleID)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
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
    
    // MARK: - Cmd+V — once only
    
    /// Post a single ⌘V through the HID tap. Do **not** also postToPid —
    /// many apps receive both and insert the clipboard twice.
    private func postCommandVOnce() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0
        
        let keyV = CGKeyCode(kVK_ANSI_V)
        
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else {
            print("❌ CGEvent create failed")
            return
        }
        
        down.flags = .maskCommand
        up.flags = .maskCommand
        
        down.post(tap: .cghidEventTap)
        // Tiny gap so the host sees a clean key down/up pair (not two pastes)
        usleep(5_000)
        up.post(tap: .cghidEventTap)
    }
    
    // MARK: - Clipboard restore
    
    private func restorePreviousClipboardIfSafe(pasted: String) {
        guard let previous = previousClipboard else { return }
        // Don't restore if previous was already our paste text
        guard previous != pasted else {
            previousClipboard = nil
            return
        }
        let pb = NSPasteboard.general
        if pb.string(forType: .string) == pasted {
            pb.clearContents()
            pb.setString(previous, forType: .string)
            print("📋 Restored previous clipboard")
        }
        previousClipboard = nil
    }
    
    // MARK: - osascript fallback
    
    private func osascriptPaste(pid: pid_t) -> Bool {
        let source = """
        tell application "System Events"
          set frontmost of first process whose unix id is \(pid) to true
          delay 0.06
          keystroke "v" using command down
        end tell
        """
        return runOSAscript(source)
    }
    
    private func osascriptPasteFront() -> Bool {
        let source = """
        tell application "System Events"
          delay 0.03
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
