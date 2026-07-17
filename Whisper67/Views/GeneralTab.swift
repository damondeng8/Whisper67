import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @Bindable var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(
                    title: "General",
                    subtitle: "Menu bar, startup, and paste behavior"
                )
                
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
                                        .fill(Color.black)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
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
