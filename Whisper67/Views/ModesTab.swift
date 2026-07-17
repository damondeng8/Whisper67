import SwiftUI

struct ModesTab: View {
    @Bindable var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(
                    title: "Dictation modes",
                    subtitle: "How your speech is written after transcription"
                )
                
                // Style picker
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Writing style")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        
                        Text("Applied every time you dictate. Cloud engines also get a matching prompt hint.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        VStack(spacing: 8) {
                            ForEach(DictationStyle.allCases) { style in
                                styleRow(style)
                            }
                        }
                    }
                    .padding(18)
                }
                
                // List mode
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 14) {
                            Image(systemName: "list.number")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DengBrand.ink)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.black.opacity(0.06)))
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Auto list")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Text(appState.listModeEnabled
                                     ? "Items become 1. 2. 3. on separate lines"
                                     : "Off — paste as a normal paragraph")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $appState.listModeEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        
                        if appState.listModeEnabled {
                            Divider().opacity(0.35)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Say things like:")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text("“First milk, second eggs, third bread”")
                                    .font(.system(size: 12, design: .rounded))
                                Text("“Milk and eggs and bread”")
                                    .font(.system(size: 12, design: .rounded))
                                Text("“Next buy stamps, then mail the letter”")
                                    .font(.system(size: 12, design: .rounded))
                                Text("→ becomes numbered lines automatically.")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 2)
                            }
                        }
                    }
                    .padding(18)
                }
                
                // Live preview
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Preview")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("Sample raw → \(appState.modeStatusLabel)")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Text(sampleRaw)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.black.opacity(0.03))
                            }
                        
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        
                        Text(appState.formatTranscript(sampleRaw))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(DengBrand.ink)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.black.opacity(0.05))
                            }
                    }
                    .padding(18)
                }
            }
            .padding(28)
        }
    }
    
    private var sampleRaw: String {
        if appState.listModeEnabled {
            return "first buy milk second get eggs third pick up bread"
        }
        switch appState.dictationStyle {
        case .formal:
            return "hey don't forget we'll need the report ready by friday"
        case .casual:
            return "hey don't forget we'll need the report ready by friday"
        case .periodsOnly:
            return "what's the plan? we'll meet at noon, then ship — ok!"
        }
    }
    
    private func styleRow(_ style: DictationStyle) -> some View {
        let selected = appState.dictationStyle == style
        return Button {
            appState.dictationStyle = style
        } label: {
            HStack(spacing: 12) {
                Image(systemName: style.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? .white : DengBrand.ink)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle()
                            .fill(selected ? DengBrand.ink : Color.black.opacity(0.06))
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DengBrand.ink)
                    Text(style.subtitle)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DengBrand.ink)
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.black.opacity(0.06) : Color.black.opacity(0.02))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                selected ? Color.black.opacity(0.14) : Color.clear,
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }
}
