import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @Bindable var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(
                    title: "General",
                    subtitle: "Menu bar, startup, and paste behavior"
                )
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Appearance")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(DengBrand.ink)
                        
                        Text("Toggle light or dark liquid glass anytime — also available in the sidebar.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(DengBrand.graphite.opacity(0.8))
                        
                        // Light ↔ Dark switch (primary control)
                        HStack {
                            Label("Light", systemImage: "sun.max.fill")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(
                                    appState.appearance == .light || (appState.appearance == .system && colorScheme == .light)
                                        ? DengBrand.ink
                                        : DengBrand.graphite.opacity(0.7)
                                )
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: {
                                    switch appState.appearance {
                                    case .dark: return true
                                    case .light: return false
                                    case .system: return colorScheme == .dark
                                    }
                                },
                                set: { isDark in
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                        appState.appearance = isDark ? .dark : .light
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(DengBrand.glow)
                            
                            Spacer()
                            
                            Label("Dark", systemImage: "moon.fill")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(
                                    appState.appearance == .dark || (appState.appearance == .system && colorScheme == .dark)
                                        ? DengBrand.ink
                                        : DengBrand.graphite.opacity(0.7)
                                )
                        }
                        .padding(.horizontal, 4)
                        
                        Divider().opacity(0.4)
                        
                        // Full mode picker including Auto
                        HStack(spacing: 8) {
                            ForEach(AppAppearance.allCases) { mode in
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        appState.appearance = mode
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: mode.icon)
                                            .font(.system(size: 14, weight: .semibold))
                                        Text(mode.title)
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundStyle(DengBrand.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background {
                                        SelectChipBackground(
                                            isSelected: appState.appearance == mode,
                                            cornerRadius: 12
                                        )
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(18)
                }
                
                GlassCard {
                    VStack(spacing: 0) {
                        GlassSettingRow(
                            title: "Menu bar icon",
                            subtitle: "Show Whisper67 in the menu bar for quick access"
                        ) {
                            Toggle("", isOn: $appState.showMenuBarIcon)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        
                        Divider().padding(.leading, 16)
                        
                        GlassSettingRow(
                            title: "Launch at login",
                            subtitle: "Start Whisper67 when you log in to your Mac"
                        ) {
                            Toggle("", isOn: Binding(
                                get: { appState.launchAtLogin },
                                set: { newValue in
                                    appState.launchAtLogin = newValue
                                    updateLoginItem(newValue)
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }
                        
                        Divider().padding(.leading, 16)
                        
                        GlassSettingRow(
                            title: "Auto-paste at cursor",
                            subtitle: "Insert text where your caret is in the active app"
                        ) {
                            Toggle("", isOn: $appState.autoPaste)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(DengBrand.ink)
                        }
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        
                        HStack(spacing: 12) {
                            Image("Whisper67Logo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(9)
                                .frame(width: 52, height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.12, green: 0.13, blue: 0.18),
                                                    Color(red: 0.04, green: 0.05, blue: 0.08)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(DengBrand.name)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                Text("Version 1.0 · Liquid glass dictation for macOS")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text(DengBrand.tagline)
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(18)
                }
            }
            .padding(28)
        }
    }
    
    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Login item error: \(error)")
        }
    }
}
