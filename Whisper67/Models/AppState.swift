import Foundation
import Observation
import Security

// MARK: - Transcription Provider

enum TranscriptionProvider: String, CaseIterable, Identifiable, Codable {
    case local = "local"
    case openAI = "openai"
    case groq = "groq"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .local: return "Local (WhisperKit)"
        case .openAI: return "OpenAI Whisper"
        case .groq: return "Groq Whisper"
        }
    }
    
    var subtitle: String {
        switch self {
        case .local: return "On-device · private · free"
        case .openAI: return "whisper-1 · cloud API"
        case .groq: return "whisper-large-v3-turbo · fast & cheap"
        }
    }
    
    var icon: String {
        switch self {
        case .local: return "laptopcomputer"
        case .openAI: return "sparkles"
        case .groq: return "bolt.fill"
        }
    }
    
    var signupURL: URL? {
        switch self {
        case .local: return nil
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .groq: return URL(string: "https://console.groq.com/keys")
        }
    }
    
    var docsURL: URL? {
        switch self {
        case .local: return nil
        case .openAI: return URL(string: "https://platform.openai.com/docs/guides/speech-to-text")
        case .groq: return URL(string: "https://console.groq.com/docs/speech-to-text")
        }
    }
    
    var defaultModel: String {
        switch self {
        case .local: return "tiny" // fastest local; switch to base/small in Settings for accuracy
        case .openAI: return "whisper-1"
        case .groq: return "whisper-large-v3-turbo"
        }
    }
    
    var isCloud: Bool {
        self == .openAI || self == .groq
    }
}

// MARK: - Dictation style modes

enum DictationStyle: String, CaseIterable, Identifiable, Codable {
    case formal
    case casual
    case periodsOnly
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .periodsOnly: return "Periods only"
        }
    }
    
    var subtitle: String {
        switch self {
        case .formal:
            return "Polished prose · full punctuation"
        case .casual:
            return "Natural spoken tone"
        case .periodsOnly:
            return "Formal feel · mainly periods (no commas/!/?)"
        }
    }
    
    var icon: String {
        switch self {
        case .formal: return "text.alignleft"
        case .casual: return "bubble.left"
        case .periodsOnly: return "textformat.abc"
        }
    }
    
    /// Whisper prompt bias for cloud (and soft local hint).
    var whisperHint: String {
        switch self {
        case .formal:
            return "Transcribe in clear formal English with proper capitalization and punctuation."
        case .casual:
            return "Transcribe naturally in a casual conversational tone."
        case .periodsOnly:
            return "Transcribe formally using periods to end sentences. Avoid commas, question marks, and exclamation points."
        }
    }
}

// MARK: - Custom Word

struct CustomWord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var word: String
    var createdAt: Date = Date()
    
    init(word: String) {
        self.word = word.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Usage Stats

struct UsageStats: Codable, Equatable {
    var totalWords: Int = 0
    var totalCharacters: Int = 0
    var totalSessions: Int = 0
    var totalAudioSeconds: Double = 0
    var totalAPIRequests: Int = 0
    /// Approximate "token" units for cloud usage display (chars / 4, similar to GPT tokenization heuristic)
    var totalAPITokens: Int = 0
    var lastDictationAt: Date?
    
    var formattedWords: String {
        totalWords.formatted(.number.notation(.compactName))
    }
    
    var formattedTokens: String {
        totalAPITokens.formatted(.number.notation(.compactName))
    }
    
    var formattedAudioMinutes: String {
        let minutes = totalAudioSeconds / 60.0
        if minutes < 1 {
            return String(format: "%.0fs", totalAudioSeconds)
        }
        return String(format: "%.1f min", minutes)
    }
    
    mutating func record(text: String, audioSeconds: Double, usedCloudAPI: Bool) {
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        totalWords += words
        totalCharacters += text.count
        totalSessions += 1
        totalAudioSeconds += max(0, audioSeconds)
        lastDictationAt = Date()
        if usedCloudAPI {
            totalAPIRequests += 1
            // Heuristic token estimate for display (Whisper bills by audio time, not tokens)
            totalAPITokens += max(1, text.count / 4)
        }
    }
}

// MARK: - Keychain Helper

enum KeychainStore {
    private static let service = "com.whisper67.app.apikeys"
    
    static func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
    
    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - App State

@Observable
final class AppState {
    static let shared = AppState()
    
    // Provider & models
    var provider: TranscriptionProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: Keys.provider) }
    }
    
    var localModel: String {
        didSet { UserDefaults.standard.set(localModel, forKey: Keys.localModel) }
    }
    
    var language: String {
        didSet { UserDefaults.standard.set(language, forKey: Keys.language) }
    }
    
    var hotkey: String {
        didSet { UserDefaults.standard.set(hotkey, forKey: Keys.hotkey) }
    }
    
    var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: Keys.menuBar) }
    }
    
    var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }
    
    var autoPaste: Bool {
        didSet { UserDefaults.standard.set(autoPaste, forKey: Keys.autoPaste) }
    }
    
    /// When false, Control hold / double-tap do nothing. Classic toggle hotkey still works.
    var controlPushToTalkEnabled: Bool {
        didSet { UserDefaults.standard.set(controlPushToTalkEnabled, forKey: Keys.controlPTT) }
    }
    
    /// Writing style applied after transcription (and as a Whisper prompt hint).
    var dictationStyle: DictationStyle {
        didSet { UserDefaults.standard.set(dictationStyle.rawValue, forKey: Keys.dictationStyle) }
    }
    
    /// When on, spoken lists become numbered 1. 2. 3. lines.
    var listModeEnabled: Bool {
        didSet { UserDefaults.standard.set(listModeEnabled, forKey: Keys.listMode) }
    }
    
    // API keys (in-memory + Keychain)
    var openAIKey: String = "" {
        didSet {
            if openAIKey.isEmpty {
                KeychainStore.delete(account: Keys.openAIKey)
            } else {
                KeychainStore.set(openAIKey, account: Keys.openAIKey)
            }
        }
    }
    
    var groqKey: String = "" {
        didSet {
            if groqKey.isEmpty {
                KeychainStore.delete(account: Keys.groqKey)
            } else {
                KeychainStore.set(groqKey, account: Keys.groqKey)
            }
        }
    }
    
    var customWords: [CustomWord] = [] {
        didSet {
            guard !isHydrating else { return }
            persistCustomWords()
        }
    }
    
    var usageStats: UsageStats = UsageStats() {
        didSet {
            guard !isHydrating else { return }
            persistUsageStats()
        }
    }
    
    /// Blocks persist during init so empty defaults never wipe disk.
    private var isHydrating = true
    
    private enum Keys {
        static let provider = "whisper67.provider"
        static let localModel = "whisper67.localModel"
        static let language = "whisper67.language"
        static let hotkey = "whisper67.hotkey"
        static let menuBar = "whisper67.menuBar"
        static let launchAtLogin = "whisper67.launchAtLogin"
        static let autoPaste = "whisper67.autoPaste"
        static let controlPTT = "whisper67.controlPushToTalk"
        static let dictationStyle = "whisper67.dictationStyle"
        static let listMode = "whisper67.listMode"
        static let openAIKey = "openai_api_key"
        static let groqKey = "groq_api_key"
        static let customWords = "whisper67.customWords"
        static let usageStats = "whisper67.usageStats"
    }
    
    private init() {
        let defaults = UserDefaults.standard
        let storedOpenAI = KeychainStore.get(account: Keys.openAIKey) ?? ""
        let storedGroq = KeychainStore.get(account: Keys.groqKey) ?? ""
        
        // Initialize all stored properties first (persist suppressed via isHydrating)
        if let raw = defaults.string(forKey: Keys.provider),
           let p = TranscriptionProvider(rawValue: raw) {
            provider = p
        } else {
            // Prefer Groq if key exists, otherwise local so the app works out of the box
            provider = storedGroq.isEmpty ? .local : .groq
        }
        localModel = defaults.string(forKey: Keys.localModel) ?? "tiny"
        language = defaults.string(forKey: Keys.language) ?? "auto"
        
        // ⌃Space conflicts with macOS "Select previous input source" — migrate away
        let savedHotkey = defaults.string(forKey: Keys.hotkey) ?? "⌥Space"
        if savedHotkey == "⌃Space" {
            hotkey = "⌥Space"
            defaults.set("⌥Space", forKey: Keys.hotkey)
        } else {
            hotkey = savedHotkey
        }
        
        showMenuBarIcon = defaults.object(forKey: Keys.menuBar) as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        // Auto-paste at cursor is the core product behavior — keep ON
        autoPaste = true
        defaults.set(true, forKey: Keys.autoPaste)
        
        // Default ON for Control PTT unless user previously turned it off
        if defaults.object(forKey: Keys.controlPTT) == nil {
            controlPushToTalkEnabled = true
        } else {
            controlPushToTalkEnabled = defaults.bool(forKey: Keys.controlPTT)
        }
        
        if let raw = defaults.string(forKey: Keys.dictationStyle),
           let style = DictationStyle(rawValue: raw) {
            dictationStyle = style
        } else {
            dictationStyle = .casual
        }
        listModeEnabled = defaults.bool(forKey: Keys.listMode)
        
        // Load dictionary + stats BEFORE clearing hydrate flag (never wipe on boot)
        if let data = defaults.data(forKey: Keys.customWords),
           let words = try? JSONDecoder().decode([CustomWord].self, from: data) {
            customWords = words
        } else {
            customWords = []
        }
        if let data = defaults.data(forKey: Keys.usageStats),
           let stats = try? JSONDecoder().decode(UsageStats.self, from: data) {
            usageStats = stats
        } else {
            usageStats = UsageStats()
        }
        
        openAIKey = storedOpenAI
        groqKey = storedGroq
        
        isHydrating = false
    }
    
    var apiKeyForCurrentProvider: String {
        switch provider {
        case .openAI: return openAIKey
        case .groq: return groqKey
        case .local: return ""
        }
    }
    
    var isProviderConfigured: Bool {
        switch provider {
        case .local: return true
        case .openAI: return !openAIKey.trimmingCharacters(in: .whitespaces).isEmpty
        case .groq: return !groqKey.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
    
    /// Prompt hint for Whisper APIs to bias vocabulary (custom dictionary).
    var dictionaryPrompt: String {
        let words = customWords.map(\.word).filter { !$0.isEmpty }
        guard !words.isEmpty else { return "" }
        return "Vocabulary: " + words.joined(separator: ", ") + "."
    }
    
    /// Full prompt sent to Whisper: style + optional list bias + dictionary.
    var transcriptionPrompt: String {
        var parts: [String] = [dictationStyle.whisperHint]
        if listModeEnabled {
            parts.append("If the speaker lists items, number them as 1. 2. 3. on separate lines.")
        }
        let dict = dictionaryPrompt
        if !dict.isEmpty { parts.append(dict) }
        return parts.joined(separator: " ")
    }
    
    /// Apply style + list post-processing to a finished transcript.
    func formatTranscript(_ raw: String) -> String {
        TranscriptFormatter.format(raw, style: dictationStyle, listMode: listModeEnabled)
    }
    
    var modeStatusLabel: String {
        var label = dictationStyle.displayName
        if listModeEnabled { label += " · Lists" }
        return label
    }
    
    func addCustomWord(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !customWords.contains(where: { $0.word.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        var next = customWords
        next.insert(CustomWord(word: trimmed), at: 0)
        customWords = next
        persistCustomWords() // explicit — don't rely only on didSet under @Observable
    }
    
    func removeCustomWord(_ word: CustomWord) {
        var next = customWords
        next.removeAll { $0.id == word.id }
        customWords = next
        persistCustomWords()
    }
    
    func recordUsage(text: String, audioSeconds: Double) {
        var stats = usageStats
        stats.record(text: text, audioSeconds: audioSeconds, usedCloudAPI: provider.isCloud)
        usageStats = stats
        persistUsageStats()
    }
    
    func resetUsageStats() {
        usageStats = UsageStats()
        persistUsageStats()
    }
    
    private func persistCustomWords() {
        do {
            let data = try JSONEncoder().encode(customWords)
            UserDefaults.standard.set(data, forKey: Keys.customWords)
            UserDefaults.standard.synchronize()
            print("💾 Dictionary saved (\(customWords.count) words)")
        } catch {
            print("❌ Dictionary save failed: \(error)")
        }
    }
    
    private func persistUsageStats() {
        if let data = try? JSONEncoder().encode(usageStats) {
            UserDefaults.standard.set(data, forKey: Keys.usageStats)
        }
    }
}
