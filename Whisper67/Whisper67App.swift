import SwiftUI
import AppKit

@main
struct Whisper67App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Menu bar only in the Scene graph — main window is owned by AppKit
        // so "Open Settings" always works. isInserted respects General → menu bar toggle.
        MenuBarExtra(isInserted: menuBarInserted) {
            MenuBarView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)
    }
    
    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { AppState.shared.showMenuBarIcon },
            set: { AppState.shared.showMenuBarIcon = $0 }
        )
    }
}

// MARK: - Menu bar label

struct MenuBarLabel: View {
    @State private var manager = TranscriptionManager.shared
    
    var body: some View {
        let symbol: String = {
            if manager.isTranscribing {
                return manager.isStickySession ? "waveform.badge.mic" : "waveform.circle.fill"
            }
            return "waveform"
        }()
        Label("Whisper67", systemImage: symbol)
            .help(manager.statusMessage)
    }
}

// MARK: - App delegate + main window owner

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!
    
    private var backgroundActivity: NSObjectProtocol?
    private var settingsWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // Normal app with Dock icon — always openable
        NSApp.setActivationPolicy(.regular)
        
        backgroundActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical, .idleSystemSleepDisabled],
            reason: "Whisper67 global dictation"
        )
        
        // Services (dictation works even if settings closed)
        _ = TranscriptionManager.shared
        // autoPaste is loaded from UserDefaults in AppState — do not force
        TranscriptionManager.shared.requestPermissions()
        ControlDictationInput.shared.setup()
        GlobalHotkeyService.shared.currentHotkey = AppState.shared.hotkey
        GlobalHotkeyService.shared.setup()
        
        // Show main window on launch so the app is clearly "open"
        DispatchQueue.main.async {
            self.showSettingsWindow()
        }
        
        print("🚀 Whisper67 launched")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock click always shows settings
        showSettingsWindow()
        return true
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep menu bar + hotkeys alive when settings is closed
        false
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // Silent re-check only — never re-prompt TCC on focus
        PermissionManager.shared.refresh()
        ControlDictationInput.shared.ensureActiveForSession()
        GlobalHotkeyService.shared.refreshAccessibilityStatus()
    }
    
    func applicationDidResignActive(_ notification: Notification) {
        ControlDictationInput.shared.ensureActiveForSession()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let backgroundActivity {
            ProcessInfo.processInfo.endActivity(backgroundActivity)
        }
    }
    
    /// Reliable settings window (not dependent on SwiftUI openWindow).
    @objc func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        let root = SettingsView()
        
        let hosting = NSHostingController(rootView: root)
        // Compact default — fits Home + sidebar without huge empty chrome
        let defaultSize = NSSize(width: 900, height: 640)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "Whisper67"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 560)
        window.contentMinSize = NSSize(width: 820, height: 560)
        window.setContentSize(defaultSize)
        // New autosave key so older oversized frames don't restore
        window.setFrameAutosaveName("Whisper67Main.v2")
        // If no saved frame yet (or invalid), start at default centered size
        if !window.setFrameUsingName("Whisper67Main.v2") {
            window.setContentSize(defaultSize)
            window.center()
        }
        // Guard against absurd restored sizes (e.g. full-display from prior build)
        var frame = window.frame
        if let screen = window.screen ?? NSScreen.main {
            let maxW = min(screen.visibleFrame.width * 0.88, 1100)
            let maxH = min(screen.visibleFrame.height * 0.88, 820)
            if frame.width > maxW || frame.height > maxH {
                frame.size = NSSize(width: min(frame.width, maxW), height: min(frame.height, maxH))
                window.setFrame(frame, display: false)
                window.center()
            }
        }
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Menu bar menu (uses AppKit open — always works)

struct MenuBarView: View {
    @State private var appState = AppState.shared
    @State private var manager = TranscriptionManager.shared
    
    var body: some View {
        Button(manager.isTranscribing
               ? (manager.isStickySession ? "Listening (sticky)" : "Listening…")
               : "Ready") {}
            .disabled(true)
        
        Text(manager.statusMessage)
            .font(.caption)
        
        Divider()
        
        if manager.isTranscribing {
            Button("Send") {
                Task { await manager.confirmDictation() }
            }
            Button("Cancel") {
                Task { await manager.cancelTranscription() }
            }
        } else {
            Button("Start Dictation") {
                Task { await manager.toggleDictation() }
            }
        }
        
        Divider()
        
        Text("Hold ⌃ talk · Double-tap ⌃ sticky")
        Text("\(appState.hotkey) toggle · ⏎ send · esc cancel")
        
        Divider()
        
        // Quick mode switchers
        Menu("Mode: \(appState.modeStatusLabel)") {
            ForEach(DictationStyle.allCases) { style in
                Button {
                    appState.dictationStyle = style
                } label: {
                    HStack {
                        Text(style.displayName)
                        if appState.dictationStyle == style {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button {
                appState.listModeEnabled.toggle()
            } label: {
                HStack {
                    Text("Auto list")
                    if appState.listModeEnabled {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        
        Divider()
        
        Text("Words: \(appState.usageStats.formattedWords)")
        Text("Engine: \(appState.provider.displayName)")
        
        Divider()
        
        Menu("Appearance: \(appState.appearance.title)") {
            ForEach(AppAppearance.allCases) { mode in
                Button {
                    appState.appearance = mode
                } label: {
                    HStack {
                        Text(mode.title)
                        if appState.appearance == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        
        Divider()
        
        // THIS is the critical fix — AppKit, not openWindow
        Button("Open Whisper67…") {
            AppDelegate.shared?.showSettingsWindow()
        }
        
        Button("Fix Permissions…") {
            PermissionManager.shared.requestAccessibilityFromUser()
            // reinstall after user returns from Settings — force one create attempt
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                ControlDictationInput.shared.reinstallAll(forceTap: true)
            }
            AppDelegate.shared?.showSettingsWindow()
        }
        
        Divider()
        
        Button("Quit Whisper67") {
            NSApp.terminate(nil)
        }
    }
}

extension Notification.Name {
    static let whisper67ToggleDictation = Notification.Name("whisper67ToggleDictation")
}
