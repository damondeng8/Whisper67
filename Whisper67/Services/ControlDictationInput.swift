import Foundation
import AppKit
import Carbon
import ApplicationServices
import Observation

/// System-wide **Control** push-to-talk — works when Whisper67 is in the background.
///
/// Uses a **dedicated CFRunLoop thread** for the CGEvent tap so macOS does not
/// starve the tap when the app is not frontmost.
///
/// Owns only ⌃:
/// - Hold ⌃ → push-to-talk (release to send)
/// - Double-tap ⌃ → sticky
///
/// Enter / Esc during a session are owned solely by `RecordingKeyMonitor`
/// (avoids triple-handlers and double confirm).
@Observable
final class ControlDictationInput {
    static let shared = ControlDictationInput()
    
    // MARK: - Public state
    
    var isSticky = false
    private(set) var isRegistered = false
    private(set) var accessibilityTrusted = false
    private(set) var eventTapActive = false
    private(set) var globalMonitorActive = false
    private(set) var engineStatus = "Not started"
    
    var onStart: (() -> Void)?
    /// Fired when Control is released (hold-to-talk send).
    var onConfirm: (() -> Void)?
    
    var isRecording = false {
        didSet {
            if isRecording != oldValue {
                AppLog.debug("🎙 isRecording → \(isRecording) sticky=\(isSticky)")
            }
        }
    }
    
    // MARK: - Private
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var didInstallObservers = false
    private var watchdog: Timer?
    
    private var controlIsDown = false
    private var controlDownAt: Date?
    private var lastControlUpAt: Date?
    private var lastPressWasShort = false
    private var pendingShortTapWork: DispatchWorkItem?
    private var holdStartWork: DispatchWorkItem?
    private var suppressHold = false
    
    private var lastControlActionAt: Date = .distantPast
    private var lastConfirmAt: Date = .distantPast
    
    /// Prevents CGEvent.tapCreate spam (macOS re-prompts Accessibility / Input Monitoring).
    private var lastTapCreateFailed = false
    private var lastTapCreateAttempt: Date = .distantPast
    private var lastKnownAXTrusted = false
    private let tapCreateCooldown: TimeInterval = 30
    
    // Tight windows for snappy hold-to-talk; double-tap still reliable.
    private let doubleTapWindow: TimeInterval = 0.38
    private let shortTapMax: TimeInterval = 0.28
    private let shortTapWait: TimeInterval = 0.22
    private let holdStartDelay: TimeInterval = 0.05
    private let actionDebounce: TimeInterval = 0.05
    
    private let leftControl = Int64(kVK_Control)
    private let rightControl = Int64(kVK_RightControl)
    
    private init() {}
    
    // MARK: - Lifecycle
    
    func setup() {
        refreshAccessibility()
        reinstallAll(forceTap: true)
        
        guard !didInstallObservers else { return }
        didInstallObservers = true
        
        let center = NotificationCenter.default
        // Re-arm when leaving / entering foreground — critical for universal use
        for name in [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
            NSApplication.didFinishLaunchingNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshAccessibility()
                self?.ensureActiveForSession()
            }
        }
        
        // Keep-alive watchdog on main run loop
        watchdog = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.watchdogTick()
        }
        if let watchdog {
            RunLoop.main.add(watchdog, forMode: .common)
        }
    }
    
    private func watchdogTick() {
        refreshAccessibility()
        if let tap = eventTap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                print("⚠️ Event tap disabled — re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else {
            // Only recreate after AX flips false→true, or cooldown elapsed while trusted
            let axJustGranted = accessibilityTrusted && !lastKnownAXTrusted
            let cooldownOK = Date().timeIntervalSince(lastTapCreateAttempt) >= tapCreateCooldown
            if accessibilityTrusted && (axJustGranted || (cooldownOK && lastTapCreateFailed)) {
                print("⚠️ Event tap missing — careful reinstall (AX ready)")
                reinstallAll(forceTap: axJustGranted)
            }
        }
        lastKnownAXTrusted = accessibilityTrusted
        // Always ensure global monitor if AX is on
        if accessibilityTrusted && !globalMonitorActive {
            installNSEventMonitors()
            updateEngineStatus()
        }
    }
    
    /// Call often: session start, app resign active, etc.
    /// Re-enables existing taps; does not spam CGEvent.tapCreate (that re-prompts TCC).
    func ensureActiveForSession() {
        refreshAccessibility()
        if eventTapActive, let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        } else if accessibilityTrusted && !lastTapCreateFailed {
            // First successful path only when we haven't already failed
            installEventTap(force: false)
        } else if accessibilityTrusted && !lastKnownAXTrusted {
            // AX just became trusted — worth one retry
            installEventTap(force: true)
        }
        // NSEvent global monitors do not re-prompt TCC
        if accessibilityTrusted && !globalMonitorActive {
            installNSEventMonitors()
        } else if !globalMonitorActive && !eventTapActive {
            // Local-only fallback never needs special permissions
            installNSEventMonitors()
        }
        lastKnownAXTrusted = accessibilityTrusted
        isRegistered = eventTapActive || globalMonitorActive || localKeyMonitor != nil
        updateEngineStatus()
    }
    
    func refreshAccessibility() {
        // Must be called on main for reliable TCC result
        let trusted = AXIsProcessTrusted()
        DispatchQueue.main.async {
            self.accessibilityTrusted = trusted
            PermissionManager.shared.accessibilityGranted = trusted
        }
        accessibilityTrusted = trusted
    }
    
    func requestAccessibilityPrompt() {
        PermissionManager.shared.requestAccessibilityFromUser()
        refreshAccessibility()
        // Brief delay so TCC can update after user toggles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.lastTapCreateFailed = false
            self?.reinstallAll(forceTap: true)
        }
    }
    
    func reinstallAll(forceTap: Bool = false) {
        installEventTap(force: forceTap)
        installNSEventMonitors()
        isRegistered = eventTapActive || globalMonitorActive || localKeyMonitor != nil
        updateEngineStatus()
        print("⌨️ Input engine: \(engineStatus) AX=\(AXIsProcessTrusted())")
    }
    
    private func updateEngineStatus() {
        if eventTapActive && globalMonitorActive {
            engineStatus = "Universal (tap + global)"
        } else if eventTapActive {
            engineStatus = "Event tap (universal)"
        } else if globalMonitorActive {
            engineStatus = "Global monitor (universal)"
        } else if localKeyMonitor != nil {
            engineStatus = "LOCAL ONLY — enable Accessibility"
        } else {
            engineStatus = "Inactive — enable Accessibility"
        }
    }
    
    // MARK: - CGEvent tap on dedicated thread
    
    /// - Parameter force: bypass cooldown after user grants permissions.
    private func installEventTap(force: Bool = false) {
        // Already live — just ensure enabled
        if eventTapActive, let existing = eventTap {
            CGEvent.tapEnable(tap: existing, enable: true)
            return
        }
        
        // Avoid hammering CGEvent.tapCreate — macOS re-prompts Input Monitoring / AX
        if !force && lastTapCreateFailed {
            let elapsed = Date().timeIntervalSince(lastTapCreateAttempt)
            if elapsed < tapCreateCooldown {
                return
            }
        }
        
        // Prefer waiting until AX reports true to reduce failed creates (and prompts)
        if !force && !AXIsProcessTrusted() {
            lastTapCreateFailed = true
            lastTapCreateAttempt = Date()
            eventTapActive = false
            return
        }
        
        lastTapCreateAttempt = Date()
        tearDownTap()
        eventTapActive = false
        
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        
        // Prefer HID (works better system-wide), then session
        let locations: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]
        
        var createdTap: CFMachPort?
        var usedLocation = "none"
        
        for location in locations {
            if let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let svc = Unmanaged<ControlDictationInput>.fromOpaque(refcon).takeUnretainedValue()
                    return svc.handleCGEvent(type: type, event: event)
                },
                userInfo: userInfo
            ) {
                createdTap = tap
                usedLocation = (location == .cghidEventTap) ? "hid" : "session"
                break
            }
        }
        
        guard let tap = createdTap else {
            print("⚠️ CGEvent.tapCreate failed — grant Accessibility + Input Monitoring for Whisper67 (will not re-prompt until granted or cooldown)")
            lastTapCreateFailed = true
            eventTapActive = false
            return
        }
        
        lastTapCreateFailed = false
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        
        // Dedicated thread so background app still receives events
        let thread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource else { return }
            let rl = CFRunLoopGetCurrent()
            self.tapRunLoop = rl
            CFRunLoopAddSource(rl, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("✅ CGEvent tap on background thread (\(usedLocation))")
            // Run forever until stopped
            while !Thread.current.isCancelled {
                CFRunLoopRunInMode(.defaultMode, 0.5, false)
            }
            CFRunLoopRemoveSource(rl, source, .commonModes)
        }
        thread.name = "whisper67.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread
        
        eventTapActive = true
        accessibilityTrusted = true
        DispatchQueue.main.async {
            PermissionManager.shared.accessibilityGranted = true
            self.accessibilityTrusted = true
        }
    }
    
    private func tearDownTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tapThread?.cancel()
        if let rl = tapRunLoop {
            CFRunLoopStop(rl)
        }
        if let source = runLoopSource, let rl = tapRunLoop {
            CFRunLoopRemoveSource(rl, source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil
        eventTapActive = false
    }
    
    private func handleCGEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        if type == .flagsChanged {
            handleFlagsChanged(event.flags)
            return Unmanaged.passUnretained(event)
        }
        
        if keyCode == leftControl || keyCode == rightControl {
            if type == .keyDown { noteControlDownFromKeyEvent() }
            else if type == .keyUp { noteControlUpFromKeyEvent() }
            return Unmanaged.passUnretained(event)
        }
        
        // Enter/Esc: RecordingKeyMonitor only (while a session is open)
        return Unmanaged.passUnretained(event)
    }
    
    // MARK: - Control hold / double-tap
    
    /// Control hold / double-tap master switch (classic hotkey is separate).
    private var isControlPTTEnabled: Bool {
        AppState.shared.controlPushToTalkEnabled
    }
    
    private func handleFlagsChanged(_ flags: CGEventFlags) {
        guard isControlPTTEnabled else {
            // Reset any half-state if user disabled mid-hold
            if controlIsDown {
                controlIsDown = false
                holdStartWork?.cancel()
                holdStartWork = nil
                controlDownAt = nil
                suppressHold = false
            }
            return
        }
        
        let controlNow = flags.contains(.maskControl)
        let otherMods = flags.contains(.maskCommand)
            || flags.contains(.maskAlternate)
            || flags.contains(.maskShift)
        
        if controlNow && otherMods {
            holdStartWork?.cancel()
            holdStartWork = nil
            suppressHold = true
            if !controlIsDown {
                controlIsDown = true
                controlDownAt = Date()
            }
            return
        }
        
        if controlNow && !controlIsDown {
            controlIsDown = true
            suppressHold = false
            handleControlDown()
        } else if !controlNow && controlIsDown {
            controlIsDown = false
            let wasSuppressed = suppressHold
            suppressHold = false
            if wasSuppressed {
                holdStartWork?.cancel()
                holdStartWork = nil
                controlDownAt = nil
            } else {
                handleControlUp()
            }
        }
    }
    
    private func noteControlDownFromKeyEvent() {
        guard isControlPTTEnabled else { return }
        guard !controlIsDown else { return }
        controlIsDown = true
        suppressHold = false
        handleControlDown()
    }
    
    private func noteControlUpFromKeyEvent() {
        guard isControlPTTEnabled || controlIsDown else { return }
        guard controlIsDown else { return }
        controlIsDown = false
        if suppressHold {
            suppressHold = false
            holdStartWork?.cancel()
            holdStartWork = nil
            controlDownAt = nil
            return
        }
        handleControlUp()
    }
    
    private func handleControlDown() {
        guard isControlPTTEnabled else { return }
        
        pendingShortTapWork?.cancel()
        pendingShortTapWork = nil
        holdStartWork?.cancel()
        holdStartWork = nil
        
        let now = Date()
        guard now.timeIntervalSince(lastControlActionAt) > actionDebounce else { return }
        lastControlActionAt = now
        
        if isRecording && isSticky {
            return
        }
        
        let isDoubleTap: Bool = {
            guard let lastUp = lastControlUpAt else { return false }
            return lastPressWasShort && now.timeIntervalSince(lastUp) <= doubleTapWindow
        }()
        
        controlDownAt = now
        
        if isDoubleTap {
            print("⌃⌃ double-tap → sticky")
            isSticky = true
            lastControlUpAt = nil
            lastPressWasShort = false
            DispatchQueue.main.async { self.onStart?() }
            return
        }
        
        isSticky = false
        if !isRecording {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.controlIsDown, !self.suppressHold, !self.isRecording else { return }
                print("⌃ hold → start")
                self.onStart?()
            }
            holdStartWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + holdStartDelay, execute: work)
        }
    }
    
    private func handleControlUp() {
        holdStartWork?.cancel()
        holdStartWork = nil
        
        let now = Date()
        let downAt = controlDownAt ?? now
        let duration = now.timeIntervalSince(downAt)
        lastControlUpAt = now
        lastPressWasShort = duration < shortTapMax
        controlDownAt = nil
        
        if isSticky { return }
        guard isRecording else { return }
        
        if lastPressWasShort {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.isSticky || self.controlIsDown { return }
                if self.isRecording { self.fireConfirm() }
            }
            pendingShortTapWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + shortTapWait, execute: work)
        } else {
            fireConfirm()
        }
    }
    
    func resetSessionFlags() {
        isSticky = false
        pendingShortTapWork?.cancel()
        pendingShortTapWork = nil
        holdStartWork?.cancel()
        holdStartWork = nil
        suppressHold = false
    }
    
    private func fireConfirm() {
        let now = Date()
        guard now.timeIntervalSince(lastConfirmAt) > 0.25 else { return }
        lastConfirmAt = now
        AppLog.debug("⏎ Control release → confirm")
        DispatchQueue.main.async { self.onConfirm?() }
    }
    
    // MARK: - NSEvent monitors (always install global when possible)
    
    private func installNSEventMonitors() {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        localKeyMonitor = nil
        globalKeyMonitor = nil
        globalMonitorActive = false
        
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if self.handleNSEvent(event, consume: true) { return nil }
            return event
        }
        
        // Always attempt global — do not gate solely on cached AX flag
        // (addGlobalMonitor returns non-nil only when permitted)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            _ = self?.handleNSEvent(event, consume: false)
        }
        globalMonitorActive = (globalKeyMonitor != nil)
        
        if globalMonitorActive {
            print("✅ Global NSEvent monitor active (system-wide)")
        } else {
            print("⚠️ Global NSEvent monitor unavailable — enable Accessibility for Whisper67")
        }
    }
    
    @discardableResult
    private func handleNSEvent(_ event: NSEvent, consume: Bool) -> Bool {
        if event.type == .flagsChanged {
            var flags: CGEventFlags = []
            if event.modifierFlags.contains(.control) { flags.insert(.maskControl) }
            if event.modifierFlags.contains(.command) { flags.insert(.maskCommand) }
            if event.modifierFlags.contains(.option) { flags.insert(.maskAlternate) }
            if event.modifierFlags.contains(.shift) { flags.insert(.maskShift) }
            handleFlagsChanged(flags)
            return false
        }
        
        // Only Control is handled here (flagsChanged above). Enter/Esc → RecordingKeyMonitor.
        return false
    }
    
    deinit {
        watchdog?.invalidate()
        tearDownTap()
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
    }
}
