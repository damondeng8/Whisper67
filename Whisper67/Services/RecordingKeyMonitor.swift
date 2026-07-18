import Foundation
import AppKit
import Carbon
import ApplicationServices

/// Dedicated system-wide Enter (send) / Esc (cancel) while a sticky or hold session is live.
/// Separate from Control PTT so session keys keep working even if Control is disabled.
final class RecordingKeyMonitor {
    static let shared = RecordingKeyMonitor()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    
    private var fallbackLocal: Any?
    private var fallbackGlobal: Any?
    
    private var isActive = false
    private var lastFireAt: Date = .distantPast
    
    /// Skip CGEvent.tapCreate after failure until AX becomes trusted (avoids re-prompts).
    private var tapCreateBlockedUntilTrusted = false
    
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    
    private init() {}
    
    func start() {
        stop()
        isActive = true
        
        // NSEvent fallback first (no extra TCC prompts). Tap only if AX is already trusted
        // or we have not recently failed create.
        installNSEventFallback()
        if AXIsProcessTrusted() || !tapCreateBlockedUntilTrusted {
            installEventTap()
        }
        
        print("⌨️ RecordingKeyMonitor START (Enter=send, Esc=cancel)")
    }
    
    func stop() {
        isActive = false
        tearDownTap()
        
        if let local = fallbackLocal {
            NSEvent.removeMonitor(local)
            fallbackLocal = nil
        }
        if let global = fallbackGlobal {
            NSEvent.removeMonitor(global)
            fallbackGlobal = nil
        }
        print("⌨️ RecordingKeyMonitor STOP")
    }
    
    // MARK: - CGEvent tap (can swallow keys)
    
    private func installEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        
        let locations: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]
        var created: CFMachPort?
        
        for location in locations {
            if let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let monitor = Unmanaged<RecordingKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    return monitor.handleTap(type: type, event: event)
                },
                userInfo: userInfo
            ) {
                created = tap
                break
            }
        }
        
        guard let tap = created else {
            // Block further create attempts until Accessibility is granted — prevents TCC spam
            tapCreateBlockedUntilTrusted = true
            print("⚠️ RecordingKeyMonitor: CGEvent tap failed (need Accessibility) — using NSEvent only")
            return
        }
        
        tapCreateBlockedUntilTrusted = false
        
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        
        let thread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource else { return }
            let rl = CFRunLoopGetCurrent()
            self.tapRunLoop = rl
            CFRunLoopAddSource(rl, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("✅ RecordingKeyMonitor event tap on background thread")
            while !Thread.current.isCancelled {
                CFRunLoopRunInMode(.defaultMode, 0.25, false)
            }
            CFRunLoopRemoveSource(rl, source, .commonModes)
        }
        thread.name = "whisper67.sessionkeys"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread
    }
    
    private func tearDownTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tapThread?.cancel()
        if let rl = tapRunLoop {
            CFRunLoopStop(rl)
        }
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil
    }
    
    private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        guard isActive, type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        // Ignore key-repeat so one press = one confirm
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == Int64(kVK_Return) || keyCode == Int64(kVK_ANSI_KeypadEnter)
                || keyCode == Int64(kVK_Escape) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        // Block only Command (e.g. Cmd+Enter). Allow bare Enter and Control+Enter.
        if flags.contains(.maskCommand) {
            return Unmanaged.passUnretained(event)
        }
        
        switch keyCode {
        case Int64(kVK_Return), Int64(kVK_ANSI_KeypadEnter):
            fireConfirm()
            return nil // swallow so target app doesn't get a newline
        case Int64(kVK_Escape):
            fireCancel()
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
    
    // MARK: - NSEvent backup (local + global)
    
    private func installNSEventFallback() {
        fallbackLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isActive else { return event }
            if self.handleNSEvent(event) { return nil }
            return event
        }
        fallbackGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isActive else { return }
            _ = self.handleNSEvent(event)
        }
        if fallbackGlobal != nil {
            print("✅ RecordingKeyMonitor global NSEvent backup active")
        } else {
            print("⚠️ RecordingKeyMonitor global NSEvent unavailable — enable Accessibility")
        }
    }
    
    private func handleNSEvent(_ event: NSEvent) -> Bool {
        if event.isARepeat {
            switch Int(event.keyCode) {
            case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape:
                return true // swallow repeats
            default:
                return false
            }
        }
        
        if event.modifierFlags.contains(.command) { return false }
        
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            fireConfirm()
            return true
        case kVK_Escape:
            fireCancel()
            return true
        default:
            return false
        }
    }
    
    private func fireConfirm() {
        let now = Date()
        guard now.timeIntervalSince(lastFireAt) > 0.3 else { return }
        lastFireAt = now
        print("⏎ RecordingKeyMonitor → confirm")
        DispatchQueue.main.async { self.onConfirm?() }
    }
    
    private func fireCancel() {
        let now = Date()
        guard now.timeIntervalSince(lastFireAt) > 0.3 else { return }
        lastFireAt = now
        print("⎋ RecordingKeyMonitor → cancel")
        DispatchQueue.main.async { self.onCancel?() }
    }
}
