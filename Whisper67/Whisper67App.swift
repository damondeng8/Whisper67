import SwiftUI
import AppKit

@main
struct Whisper67App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Menu bar only in the Scene graph — main window is owned by AppKit
        // so "Open Settings" always works.
        MenuBarExtra {
            MenuBarView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)
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
        AppState.shared.autoPaste = true
        TranscriptionManager.shared.requestPermissions()
        ControlDictationInput.shared.setup()
        ControlDictationInput.shared.reinstallAll()
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
            .frame(minWidth: 900, minHeight: 600)
        
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "Whisper67"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("Whisper67Settings")
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
        
        // THIS is the critical fix — AppKit, not openWindow
        Button("Open Whisper67…") {
            AppDelegate.shared?.showSettingsWindow()
        }
        
        Button("Fix Permissions…") {
            PermissionManager.shared.requestAccessibilityFromUser()
            ControlDictationInput.shared.reinstallAll()
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
    static let whisper67OpenMainWindow = Notification.Name("whisper67OpenMainWindow")
}
