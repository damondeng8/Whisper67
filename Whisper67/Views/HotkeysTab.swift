import SwiftUI

struct HotkeysTab: View {
    @Bindable var appState: AppState
    var manager: TranscriptionManager
    
    private let presets = [
        "⌥Space",
        "⌃⇧Space",
        "⌘⇧D",
        "⌃⇧D",
        "F5",
        "⌥D",
        "⌘⇧Space",
        "⌃⌥Space"
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(
                    title: "Shortcuts",
                    subtitle: "Turn Control on/off and pick your toggle hotkey"
                )
                
                // Control master switch
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Control push-to-talk")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Text(appState.controlPushToTalkEnabled
                                     ? "Hold ⌃ to dictate · double-tap for sticky"
                                     : "Off — Control is ignored (use toggle hotkey only)")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { appState.controlPushToTalkEnabled },
                                set: { manager.setControlPushToTalkEnabled($0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }
                        
                        if appState.controlPushToTalkEnabled {
                            Divider().opacity(0.4)
                            
                            controlRow(
                                keys: ["⌃", "hold"],
                                title: "Hold Control",
                                detail: "Speak while holding — release to transcribe and paste"
                            )
                            
                            Divider().opacity(0.4)
                            
                            controlRow(
                                keys: ["⌃", "⌃"],
                                title: "Double-tap Control",
                                detail: "Sticky mode — stays open until Enter, shortcut again, Esc, or ✕"
                            )
                        }
                        
                        Divider().opacity(0.4)
                        
                        controlRow(
                            keys: ["⏎"],
                            title: "Enter",
                            detail: "Send in sticky mode (or while the pill is open)"
                        )
                        
                        Divider().opacity(0.4)
                        
                        controlRow(
                            keys: ["esc", "✕"],
                            title: "Escape or X",
                            detail: "Cancel without pasting"
                        )
                    }
                    .padding(18)
                }
                
                // Classic toggle hotkey
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Toggle shortcut")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        
                        Text(appState.controlPushToTalkEnabled
                             ? "Press once to start sticky dictation, press again to send. Works alongside Control hold."
                             : "Your only start/stop key while Control is off. Press once to start, again to send.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Text("Current")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                            KeyBadge(keys: parseHotkey(appState.hotkey))
                        }
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 10) {
                            ForEach(presets, id: \.self) { preset in
                                Button {
                                    manager.updateHotkey(preset)
                                } label: {
                                    HStack {
                                        Spacer()
                                        KeyBadge(keys: parseHotkey(preset))
                                        Spacer()
                                    }
                                    .padding(.vertical, 12)
                                    .background {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(appState.hotkey == preset
                                                  ? Color.black.opacity(0.07)
                                                  : Color.black.opacity(0.03))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .strokeBorder(
                                                        appState.hotkey == preset
                                                            ? Color.black.opacity(0.16)
                                                            : Color.clear,
                                                        lineWidth: 1
                                                    )
                                            }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(18)
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("How it works", systemImage: "info.circle.fill")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(DengBrand.ink)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            if appState.controlPushToTalkEnabled {
                                howRow("1", "Hold ⌃ and speak — release to paste")
                                howRow("2", "Or press \(appState.hotkey) to start sticky mode")
                            } else {
                                howRow("1", "Press \(appState.hotkey) to start sticky mode")
                            }
                            howRow(appState.controlPushToTalkEnabled ? "3" : "2",
                                   "Press \(appState.hotkey) again or ⏎ Enter to send")
                            howRow(appState.controlPushToTalkEnabled ? "4" : "3",
                                   "Esc or ✕ cancels without pasting")
                        }
                    }
                    .padding(18)
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Accessibility")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("Global shortcuts need Accessibility so they work while other apps are focused.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Button("Open Accessibility Settings") {
                            PermissionManager.shared.requestAccessibilityFromUser()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(18)
                }
            }
            .padding(28)
        }
    }
    
    private func controlRow(keys: [String], title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            KeyBadge(keys: keys)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DengBrand.ink)
                Text(detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(DengBrand.graphite.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
    }
    
    private func howRow(_ badge: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(badge)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(DengBrand.ink))
            Text(text)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(DengBrand.ink.opacity(0.85))
        }
    }
    
    private func parseHotkey(_ hotkey: String) -> [String] {
        var components: [String] = []
        if hotkey.contains("⌃") { components.append("⌃") }
        if hotkey.contains("⌥") { components.append("⌥") }
        if hotkey.contains("⇧") { components.append("⇧") }
        if hotkey.contains("⌘") { components.append("⌘") }
        let mainKey = hotkey
            .replacingOccurrences(of: "⌃", with: "")
            .replacingOccurrences(of: "⌥", with: "")
            .replacingOccurrences(of: "⇧", with: "")
            .replacingOccurrences(of: "⌘", with: "")
            .trimmingCharacters(in: .whitespaces)
        if !mainKey.isEmpty { components.append(mainKey) }
        return components.isEmpty ? ["⌥", "Space"] : components
    }
}
