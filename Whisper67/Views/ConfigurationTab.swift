import SwiftUI

struct ConfigurationTab: View {
    @Bindable var whisperService: WhisperService
    @State private var selectedLanguage = "auto"
    @State private var processingMode: ProcessingMode = .standard
    
    enum ProcessingMode: String, CaseIterable {
        case fast = "Fast"
        case standard = "Standard"
        case accurate = "High Quality"
        case pro = "Professional"
        case ultra = "Ultra"
        
        var description: String {
            switch self {
            case .fast: return "Quick transcription"
            case .standard: return "Balanced speed/quality"
            case .accurate: return "Good for most uses"
            case .pro: return "High accuracy"
            case .ultra: return "Maximum accuracy (Slow)"
            }
        }
        
        var sizeDescription: String {
            switch self {
            case .fast: return "tiny • ~39MB"
            case .standard: return "base • ~74MB"
            case .accurate: return "small • ~244MB"
            case .pro: return "medium • ~769MB"
            case .ultra: return "large • ~1.5GB"
            }
        }
        
        var whisperModel: String {
            switch self {
            case .fast: return "tiny"
            case .standard: return "base"
            case .accurate: return "small"
            case .pro: return "medium"
            case .ultra: return "large"
            }
        }
    }
    
    private let availableLanguages = ["auto", "en", "es", "fr", "de", "it", "pt", "ru", "ja", "zh"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Simple header without overwhelming details
            VStack(alignment: .leading, spacing: 4) {
                Text("Audio & Models")
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .foregroundColor(.primary)
                
                Text("Configure speech recognition")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            // Clean, minimal settings in macOS style
            VStack(spacing: 1) {
                // Performance Mode - Simple selection with status
                MacOSSettingRow(
                    title: "Model",
                    subtitle: "\(processingMode.description) • \(processingMode.sizeDescription)"
                ) {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 8) {
                            Picker("Model", selection: $processingMode) {
                                ForEach(ProcessingMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 140)
                            .onChange(of: processingMode) { _, newMode in
                                whisperService.changeModel(newMode.whisperModel)
                            }
                            
                            // Model Status Indicator
                            ModelStatusView(
                                status: whisperService.modelStatus,
                                progress: whisperService.downloadProgress
                            )
                        }
                    }
                }
                
                Divider()
                
                // Audio Input - Simplified
                MacOSSettingRow(
                    title: "Microphone",
                    subtitle: "System Default"
                ) {
                    Picker("Microphone", selection: .constant("System Default" as String)) {
                        Text("System Default").tag("System Default")
                        Text("Built-in Microphone").tag("Built-in")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
                
                Divider()
                
                // Language - Simple
                MacOSSettingRow(
                    title: "Language",
                    subtitle: selectedLanguage == "auto" ? "Auto-detect" : selectedLanguage.uppercased()
                ) {
                    Picker("Language", selection: $selectedLanguage) {
                        ForEach(availableLanguages, id: \.self) { lang in
                            Text(lang == "auto" ? "Auto-detect" : lang.uppercased()).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
            }
            .background(DengBrand.chip)
            .cornerRadius(8)
            .padding(.horizontal, 24)
            
            // Storage Information
            if whisperService.isLoading || whisperService.modelStatus != .notLoaded {
                VStack(spacing: 1) {
                    MacOSSettingRow(
                        title: "Storage",
                        subtitle: "Downloaded models and cache"
                    ) {
                        VStack(alignment: .trailing, spacing: 2) {
                            if whisperService.isLoading {
                                Text("Downloading...")
                                    .font(.system(size: 11))
                                    .foregroundColor(.blue)
                                Text("\(Int(whisperService.downloadProgress * 100))%")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            } else {
                                Text(estimatedStorageUsed())
                                    .font(.system(size: 11))
                                    .foregroundStyle(DengBrand.ink)
                                Text("Used")
                                    .font(.system(size: 10))
                                    .foregroundStyle(DengBrand.graphite)
                            }
                        }
                    }
                }
                .background(DengBrand.chip)
                .cornerRadius(8)
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            
            Spacer()
        }
        .background(Color.clear)
        .onAppear {
            // Set the processing mode to match the current whisper model
            switch whisperService.selectedModel {
            case "tiny":
                processingMode = .fast
            case "base":
                processingMode = .standard
            case "small":
                processingMode = .accurate
            case "medium":
                processingMode = .pro
            case "large":
                processingMode = .ultra
            default:
                processingMode = .standard
            }
        }
    }
    
    private func modelDescription(for model: String) -> String {
        switch model {
        case "tiny": return "Fastest processing, basic accuracy (39 MB) • Best for real-time transcription"
        case "base": return "Balanced speed and accuracy (74 MB) • Recommended for most users"
        case "small": return "Better accuracy, moderate speed (244 MB) • Good for detailed transcription"
        case "medium": return "High accuracy, slower processing (769 MB) • Professional quality"
        case "large": return "Maximum accuracy, slowest speed (1550 MB) • Best quality available"
        default: return "Select a model to see details"
        }
    }
    
    private func estimatedStorageUsed() -> String {
        switch whisperService.selectedModel {
        case "tiny":
            return "39 MB"
        case "base":
            return "74 MB"
        case "small":
            return "244 MB"
        case "medium":
            return "769 MB"
        case "large":
            return "1.5 GB"
        default:
            return "Unknown"
        }
    }
}

struct MacOSSettingRow<Content: View>: View {
    let title: String
    let subtitle: String
    let content: () -> Content
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black)
                
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.black.opacity(0.6))
                    .lineLimit(1)
            }
            
            Spacer()
            
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.clear)
    }
}

struct ModelStatusView: View {
    let status: WhisperService.ModelStatus
    let progress: Double
    
    var body: some View {
        HStack(spacing: 6) {
            switch status {
            case .notLoaded:
                Image(systemName: "cloud.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("Not downloaded")
                    .font(.system(size: 10))
                    .foregroundColor(.black.opacity(0.6))
                
            case .downloading:
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Downloading...")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 9))
                        .foregroundColor(.black.opacity(0.6))
                }
                
            case .loaded:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
                Text("Ready")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                Text("Error")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }
        }
        .frame(minWidth: 80, alignment: .trailing)
    }
}