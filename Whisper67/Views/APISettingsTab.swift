import SwiftUI

struct APISettingsTab: View {
    @Bindable var appState: AppState
    @Bindable var manager: TranscriptionManager
    @State private var showOpenAIKey = false
    @State private var showGroqKey = false
    @State private var testMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(
                    title: "API",
                    subtitle: "Connect OpenAI Whisper or Groq Whisper for cloud transcription"
                )
                
                // Provider picker cards
                VStack(spacing: 12) {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        providerCard(provider)
                    }
                }
                
                // Keys
                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        GlassSettingRow(
                            title: "OpenAI API key",
                            subtitle: "platform.openai.com · model whisper-1"
                        ) {
                            HStack(spacing: 8) {
                                SecureField("sk-…", text: $appState.openAIKey)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 220)
                                    .font(.system(size: 12, design: .monospaced))
                                
                                if let url = TranscriptionProvider.openAI.signupURL {
                                    Link(destination: url) {
                                        Image(systemName: "arrow.up.right.square")
                                    }
                                    .help("Get an OpenAI API key")
                                }
                            }
                        }
                        
                        Divider().padding(.leading, 16)
                        
                        GlassSettingRow(
                            title: "Groq API key",
                            subtitle: "console.groq.com · whisper-large-v3-turbo"
                        ) {
                            HStack(spacing: 8) {
                                SecureField("gsk_…", text: $appState.groqKey)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 220)
                                    .font(.system(size: 12, design: .monospaced))
                                
                                if let url = TranscriptionProvider.groq.signupURL {
                                    Link(destination: url) {
                                        Image(systemName: "arrow.up.right.square")
                                    }
                                    .help("Get a free Groq API key")
                                }
                            }
                        }
                    }
                }
                
                // Quick links
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Get your keys")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        
                        linkRow(
                            title: "OpenAI API keys",
                            detail: "Create a secret key for Whisper",
                            url: "https://platform.openai.com/api-keys"
                        )
                        linkRow(
                            title: "OpenAI Speech-to-text docs",
                            detail: "API reference for /v1/audio/transcriptions",
                            url: "https://platform.openai.com/docs/guides/speech-to-text"
                        )
                        linkRow(
                            title: "Groq Console keys",
                            detail: "Free tier · extremely fast Whisper",
                            url: "https://console.groq.com/keys"
                        )
                        linkRow(
                            title: "Groq Speech-to-text docs",
                            detail: "whisper-large-v3-turbo on Groq",
                            url: "https://console.groq.com/docs/speech-to-text"
                        )
                    }
                    .padding(18)
                }
                
                // Local model options when local selected
                if appState.provider == .local {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Local model")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            
                            Picker("Model", selection: Binding(
                                get: { appState.localModel },
                                set: { newValue in
                                    appState.localModel = newValue
                                    manager.localWhisper.changeModel(newValue)
                                }
                            )) {
                                Text("Tiny (fast)").tag("tiny")
                                Text("Base (balanced)").tag("base")
                                Text("Small").tag("small")
                                Text("Medium").tag("medium")
                                Text("Large").tag("large")
                            }
                            .pickerStyle(.segmented)
                            
                            HStack {
                                Text(manager.localWhisper.modelStatus.description)
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if manager.localWhisper.isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        }
                        .padding(18)
                    }
                }
                
                // Language
                GlassCard {
                    GlassSettingRow(
                        title: "Language",
                        subtitle: "Hint for cloud models (auto-detect recommended)"
                    ) {
                        Picker("", selection: $appState.language) {
                            Text("Auto").tag("auto")
                            Text("English").tag("en")
                            Text("Spanish").tag("es")
                            Text("French").tag("fr")
                            Text("German").tag("de")
                            Text("Japanese").tag("ja")
                            Text("Chinese").tag("zh")
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                }
                
                // Usage summary
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Usage")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Spacer()
                            Button("Reset stats") {
                                appState.resetUsageStats()
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11, design: .rounded))
                        }
                        
                        HStack(spacing: 24) {
                            metric("Words", appState.usageStats.formattedWords)
                            metric("API tokens*", appState.usageStats.formattedTokens)
                            metric("Requests", "\(appState.usageStats.totalAPIRequests)")
                            metric("Audio", appState.usageStats.formattedAudioMinutes)
                        }
                        
                        Text("*Token estimate ≈ characters ÷ 4 for display. Cloud Whisper is billed by audio minutes.")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(18)
                }
            }
            .padding(28)
        }
    }
    
    private func providerCard(_ provider: TranscriptionProvider) -> some View {
        Button {
            appState.provider = provider
            manager.providerChanged()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(appState.provider == provider ? Color.black.opacity(0.08) : Color.black.opacity(0.04))
                        .frame(width: 44, height: 44)
                    Image(systemName: provider.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(appState.provider == provider ? DengBrand.ink : DengBrand.silver)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.displayName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(provider.subtitle)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if appState.provider == provider {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DengBrand.ink)
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                appState.provider == provider
                                    ? Color.black.opacity(0.18)
                                    : Color.white.opacity(0.45),
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }
    
    private func linkRow(title: String, detail: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
    
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
