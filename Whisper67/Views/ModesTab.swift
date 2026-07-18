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
                
                // OSS fixer toggle + strength slider
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 14) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DengBrand.ink)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(DengBrand.chipInset))
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text("OSS fixer")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Text(aiPolishSubtitle)
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $appState.aiPolishEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        
                        if appState.aiPolishEnabled {
                            Divider().opacity(0.35)
                            
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Fix strength")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    Spacer()
                                    Text(appState.aiPolishStrengthLabel)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(DengBrand.ink)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background {
                                            Capsule().fill(DengBrand.chipInset)
                                        }
                                }
                                
                                Slider(value: $appState.aiPolishStrength, in: 0...1, step: 0.05)
                                    .tint(DengBrand.ink)
                                
                                HStack {
                                    Text("Light")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                    Text("Balanced")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                    Text("Strong")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                }
                                
                                Text(appState.aiPolishStrengthDetail)
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                // Tier bullets
                                VStack(alignment: .leading, spacing: 4) {
                                    strengthBullet("Light", "Word intention, fillers, near-homophones")
                                    strengthBullet("Balanced", "+ light grammar & punctuation")
                                    strengthBullet("Strong", "+ full grammar, smoother & more formal prose")
                                }
                                .padding(.top, 2)
                                
                                Text("Model: \(TranscriptCleanupService.modelID) · Groq key · fails open to raw")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 2)
                                
                                if appState.groqKey.trimmingCharacters(in: .whitespaces).isEmpty {
                                    Text("Add a Groq key in the API tab to run the OSS fixer.")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.orange)
                                        .padding(.top, 2)
                                }
                            }
                        }
                    }
                    .padding(18)
                }
                
                // List mode — OSS formats lists (local splitter is fallback only)
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 14) {
                            Image(systemName: "list.number")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DengBrand.ink)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(DengBrand.chipInset))
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Auto list")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Text(listModeSubtitle)
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
                                Text("Dynamic detection — not everything becomes a list:")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text("• “Hey John, I would like some food.” → normal sentence")
                                    .font(.system(size: 12, design: .rounded))
                                Text("• “first milk second eggs third bread” → 1. 2. 3.")
                                    .font(.system(size: 12, design: .rounded))
                                Text("• “hey John first milk second eggs” → intro + list")
                                    .font(.system(size: 12, design: .rounded))
                                Text("Needs first/second, number one/two, next+then+also, etc.")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 2)
                                
                                if !appState.hasGroqKey {
                                    Text("Add a Groq key for better list formatting after detection.")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.orange)
                                        .padding(.top, 4)
                                }
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
                        Text(appState.canRunAIPolish
                             ? "Local rules only (AI polish runs on real dictations)"
                             : "Sample raw → \(appState.modeStatusLabel)")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Text(sampleRaw)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(DengBrand.chip)
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
                                    .fill(DengBrand.chip)
                            }
                    }
                    .padding(18)
                }
            }
            .padding(28)
        }
    }
    
    private var aiPolishSubtitle: String {
        if !appState.aiPolishEnabled {
            return appState.canRunOSSList
                ? "Off for polish · lists still use OSS"
                : "Off — Whisper + local intention only"
        }
        if appState.canRunAIPolish {
            return "On · \(appState.aiPolishStrengthLabel) · after every dictation"
        }
        return "On · waiting for Groq API key"
    }
    
    private var listModeSubtitle: String {
        if !appState.listModeEnabled {
            return "Off — never formats as a list"
        }
        if appState.hasGroqKey {
            return "On · smart detect (only real lists)"
        }
        return "On · local detect only (add Groq for OSS lists)"
    }
    
    private func strengthBullet(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DengBrand.ink.opacity(0.85))
            Text(detail)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
    
    private var sampleRaw: String {
        if appState.listModeEnabled {
            // Shows intro+list path (Auto list should number items, keep greeting)
            return "hey John first buy milk second get eggs third pick up bread"
        }
        switch appState.dictationStyle {
        case .raw:
            return "Hey, don't forget — we'll need the report ready by Friday at 3:30pm."
        case .casual:
            return "Hey don't forget we'll need the report ready by Friday"
        case .normal:
            return "Hey John what's the plan? We'll meet at noon then ship!"
        case .formal:
            return "hey don't forget we'll need the report ready by friday"
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
                    .foregroundStyle(DengBrand.ink)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle().fill(DengBrand.chipInset)
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DengBrand.ink)
                    Text(style.subtitle)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(DengBrand.graphite)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DengBrand.ink)
                }
            }
            .padding(12)
            .background {
                SelectChipBackground(isSelected: selected, cornerRadius: 12)
            }
        }
        .buttonStyle(.plain)
    }
}
