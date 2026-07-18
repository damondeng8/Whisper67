import SwiftUI
import AVFoundation
import ApplicationServices
import AppKit

struct HomeDashboardView: View {
    @Bindable var appState: AppState
    @Bindable var manager: TranscriptionManager
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                
                // Hero dictate card
                GlassCard {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(manager.isTranscribing ? "Listening to you…" : "Dictate anywhere")
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                Text(manager.statusMessage)
                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                                    .foregroundStyle(manager.lastError == nil ? DengBrand.graphite.opacity(0.65) : DengBrand.ink.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            DengPrimaryButton(
                                title: manager.isTranscribing ? "Send (Enter)" : "Start Dictation",
                                icon: manager.isTranscribing ? "return" : "mic.fill",
                                isDestructive: false
                            ) {
                                Task { await manager.toggleDictation() }
                            }
                        }
                        
                        // Floating pill preview
                        HStack {
                            Spacer()
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(DengBrand.chipInset)
                                        .frame(width: 30, height: 30)
                                    Image(systemName: "waveform")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(DengBrand.ink)
                                        .symbolEffect(.variableColor.iterative, isActive: manager.isTranscribing)
                                }
                                
                                AnimatedAudioWaves(
                                    barCount: 12,
                                    maxHeight: 26,
                                    spacing: 2.5,
                                    color: DengBrand.ink,
                                    isActive: manager.isTranscribing,
                                    overallLevel: manager.liveAudioLevel,
                                    levels: manager.liveAudioBands
                                )
                                .frame(width: 100, height: 28)
                                
                                Text(manager.isTranscribing ? "Listening" : "Ready")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(DengBrand.graphite.opacity(0.7))
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(DengBrand.glassStroke, lineWidth: 1)
                                    }
                                    .shadow(color: DengBrand.shadow, radius: 16, y: 6)
                            }
                            Spacer()
                        }
                        
                        if let err = manager.lastError, !err.isEmpty {
                            Text(err)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(24)
                }
                
                // Editable shortcuts on Home
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Shortcuts")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Spacer()
                            Text("Changes apply immediately")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                        
                        // Control PTT toggle
                        HStack(alignment: .center, spacing: 14) {
                            KeyBadge(keys: ["⌃"])
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Control push-to-talk")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Text(appState.controlPushToTalkEnabled
                                     ? "Hold ⌃ to talk · double-tap sticky"
                                     : "Disabled — Control does nothing")
                                    .font(.system(size: 11, design: .rounded))
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
                        
                        Divider().opacity(0.35)
                        
                        // Classic toggle hotkey
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Toggle hotkey")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Spacer()
                                KeyBadge(keys: parseHotkey(appState.hotkey))
                            }
                            Text("Press once to start sticky dictation, again to send.")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 8) {
                                ForEach(homeHotkeyPresets, id: \.self) { preset in
                                    Button {
                                        manager.updateHotkey(preset)
                                    } label: {
                                        HStack {
                                            Spacer()
                                            KeyBadge(keys: parseHotkey(preset))
                                            Spacer()
                                        }
                                        .padding(.vertical, 10)
                                        .background {
                                            SelectChipBackground(
                                                isSelected: appState.hotkey == preset,
                                                cornerRadius: 10
                                            )
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        if !appState.controlPushToTalkEnabled {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(DengBrand.ink.opacity(0.7))
                                Text("Only \(appState.hotkey) starts dictation. Enter sends · Esc cancels.")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(DengBrand.wash)
                            }
                        }
                    }
                    .padding(22)
                }
                
                // Dictation modes
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Dictation mode")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Spacer()
                            Text(appState.modeStatusLabel)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack(spacing: 8) {
                            ForEach(DictationStyle.allCases) { style in
                                let selected = appState.dictationStyle == style
                                Button {
                                    appState.dictationStyle = style
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: style.icon)
                                            .font(.system(size: 12, weight: .semibold))
                                        Text(style.displayName)
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    .foregroundStyle(DengBrand.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background {
                                        SelectChipBackground(isSelected: selected, cornerRadius: 12)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        Text(appState.dictationStyle.subtitle)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Divider().opacity(0.35)
                        
                        HStack {
                            Image(systemName: "list.number")
                                .foregroundStyle(DengBrand.ink.opacity(0.8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto list")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Text("Number spoken items as 1. 2. 3.")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $appState.listModeEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                    .padding(22)
                }
                
                // Stats
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ], spacing: 14) {
                    StatTile(
                        title: "Words dictated",
                        value: appState.usageStats.formattedWords,
                        subtitle: "\(appState.usageStats.totalSessions) sessions",
                        icon: "text.word.spacing",
                        tint: DengBrand.ink
                    )
                    StatTile(
                        title: "API tokens",
                        value: appState.usageStats.formattedTokens,
                        subtitle: "\(appState.usageStats.totalAPIRequests) cloud requests",
                        icon: "number",
                        tint: DengBrand.graphite
                    )
                    StatTile(
                        title: "Audio time",
                        value: appState.usageStats.formattedAudioMinutes,
                        subtitle: "Total captured",
                        icon: "waveform",
                        tint: DengBrand.silver
                    )
                }
                
                // Engine
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Active engine")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        
                        HStack(spacing: 8) {
                            ForEach(TranscriptionProvider.allCases) { provider in
                                ProviderChip(provider: provider, isSelected: appState.provider == provider) {
                                    appState.provider = provider
                                    manager.providerChanged()
                                }
                            }
                        }
                        
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 7, height: 7)
                            Text(statusText)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let last = appState.usageStats.lastDictationAt {
                                Text("Last: \(last.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        
                        if !manager.lastTranscript.isEmpty {
                            Divider().opacity(0.35)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Last transcript")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text(manager.lastTranscript)
                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(4)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(22)
                }
                
                // Permissions
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("System access")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        
                        permissionRow(
                            title: "Microphone",
                            detail: PermissionManager.shared.microphoneStatusText,
                            ok: PermissionManager.shared.microphoneGranted
                                || AudioRecorderService.microphoneAuthorized()
                        )
                        permissionRow(
                            title: "Accessibility",
                            detail: "Control hold, Enter/Esc, paste",
                            ok: PermissionManager.shared.accessibilityGranted || manager.hotkey.isRegistered
                        )
                        permissionRow(
                            title: "Input engine",
                            detail: ControlDictationInput.shared.engineStatus,
                            ok: ControlDictationInput.shared.eventTapActive
                                || ControlDictationInput.shared.globalMonitorActive
                        )
                        permissionRow(
                            title: "Engine ready",
                            detail: appState.provider.displayName,
                            ok: engineReady
                        )
                        
                        HStack(spacing: 8) {
                            Button("Enable Microphone") {
                                PermissionManager.shared.requestMicrophoneFromUser()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button("Enable Accessibility") {
                                manager.hotkey.requestAccessibilityPrompt()
                                ControlDictationInput.shared.reinstallAll()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button("Input Monitoring") {
                                PermissionManager.shared.openInputMonitoringSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button("Refresh status") {
                                PermissionManager.shared.refresh()
                                manager.hotkey.refreshAccessibilityStatus()
                                ControlDictationInput.shared.reinstallAll()
                                manager.updateStatusMessage()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        Text("Whisper67 is a menu-bar agent: leave it running (waveform icon). You do not need the settings window open. Grant Accessibility (and Input Monitoring if listed) for /Applications/Whisper67.app so Control/Enter/Esc work in every app.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(DengBrand.graphite.opacity(0.75))
                        
                        Text(PermissionManager.shared.appPathForDisplay)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(DengBrand.silver)
                            .textSelection(.enabled)
                    }
                    .padding(20)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Home")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("System-wide AI dictation for your Mac")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if manager.isTranscribing {
                Label("Recording", systemImage: "record.circle")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(DengBrand.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(DengBrand.chipInset))
            }
        }
    }
    
    private var statusColor: Color {
        let ready: Bool
        if appState.provider == .local {
            ready = manager.localWhisper.isModelReady
        } else {
            ready = appState.isProviderConfigured
        }
        return ready ? DengBrand.ink : DengBrand.silver
    }
    
    private var statusText: String {
        if appState.provider == .local {
            return manager.localWhisper.isModelReady
                ? "Local model ready"
                : manager.localWhisper.modelStatus.description
        }
        return appState.isProviderConfigured
            ? "\(appState.provider.displayName) connected"
            : "Add API key to use \(appState.provider.displayName)"
    }
    
    private var engineReady: Bool {
        if appState.provider == .local {
            return manager.localWhisper.isModelReady
        }
        return appState.isProviderConfigured
    }
    
    private func permissionRow(title: String, detail: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? DengBrand.ink : DengBrand.silver)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DengBrand.ink)
                Text(detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(DengBrand.graphite.opacity(0.65))
            }
            Spacer()
            Text(ok ? "Granted" : "Needed")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(ok ? DengBrand.ink : DengBrand.silver)
        }
    }
    
    private let homeHotkeyPresets = [
        "⌥Space",
        "⌃⇧Space",
        "⌘⇧D",
        "⌃⇧D",
        "F5",
        "⌥D",
        "⌘⇧Space",
        "⌃⌥Space"
    ]
    
    private func parseHotkey(_ hotkey: String) -> [String] {
        var parts: [String] = []
        if hotkey.contains("⌃") { parts.append("⌃") }
        if hotkey.contains("⌥") { parts.append("⌥") }
        if hotkey.contains("⇧") { parts.append("⇧") }
        if hotkey.contains("⌘") { parts.append("⌘") }
        let main = hotkey
            .replacingOccurrences(of: "⌃", with: "")
            .replacingOccurrences(of: "⌥", with: "")
            .replacingOccurrences(of: "⇧", with: "")
            .replacingOccurrences(of: "⌘", with: "")
            .trimmingCharacters(in: .whitespaces)
        if !main.isEmpty { parts.append(main) }
        return parts.isEmpty ? ["⌥", "Space"] : parts
    }
}
