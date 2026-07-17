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
    case casual
    case normal
    case formal
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .casual: return "Casual"
        case .normal: return "Normal"
        case .formal: return "Formal"
        }
    }
    
    var subtitle: String {
        switch self {
        case .casual:
            return "lowercase · chatty · keep slang & contractions"
        case .normal:
            return "Commas for pauses · no periods"
        case .formal:
            return "Full sentences · proper caps & punctuation"
        }
    }
    
    var icon: String {
        switch self {
        case .casual: return "bubble.left"
        case .normal: return "text.alignleft"
        case .formal: return "text.book.closed"
        }
    }
    
    /// Whisper prompt bias for cloud (and soft local hint).
    var whisperHint: String {
        switch self {
        case .casual:
            return "Transcribe in casual lowercase chat style. Keep contractions and informal wording. Prefer little or no formal punctuation."
        case .normal:
            return "Transcribe as continuous text using commas for pauses. Do not use periods, question marks, or exclamation points."
        case .formal:
            return "Transcribe in formal written English with proper capitalization, full sentences, and complete punctuation."
        }
    }
    
    /// Migrate old stored raw values.
    static func fromStored(_ raw: String?) -> DictationStyle {
        guard let raw else { return .casual }
        if raw == "periodsOnly" { return .normal } // old mode → Normal
        return DictationStyle(rawValue: raw) ?? .casual
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

// MARK: - Dictation History

struct DictationHistoryEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var text: String
    var createdAt: Date = Date()
    var wordCount: Int
    var audioSeconds: Double
    var providerRaw: String
    
    init(text: String, audioSeconds: Double, provider: TranscriptionProvider) {
        self.text = text
        self.audioSeconds = max(0, audioSeconds)
        self.wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
        self.providerRaw = provider.rawValue
    }
    
    var providerDisplayName: String {
        TranscriptionProvider(rawValue: providerRaw)?.displayName ?? providerRaw
    }
    
    var preview: String {
        let oneLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if oneLine.count <= 120 { return oneLine }
        return String(oneLine.prefix(117)) + "…"
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
    
    /// When on, raw Whisper text is polished by a fast Groq LLM (llama-3.1-8b-instant).
    var aiPolishEnabled: Bool {
        didSet { UserDefaults.standard.set(aiPolishEnabled, forKey: Keys.aiPolish) }
    }
    
    /// How hard the OSS fixer rewrites: 0 = light word tweaks, 1 = grammar + formal polish.
    /// Stored 0…1. Only used when `aiPolishEnabled` is true.
    var aiPolishStrength: Double {
        didSet {
            UserDefaults.standard.set(min(1, max(0, aiPolishStrength)), forKey: Keys.aiPolishStrength)
        }
    }
    
    /// Human label for the strength slider.
    var aiPolishStrengthLabel: String {
        switch aiPolishStrength {
        case ..<0.34: return "Light"
        case ..<0.67: return "Balanced"
        default: return "Strong"
        }
    }
    
    var aiPolishStrengthDetail: String {
        switch aiPolishStrength {
        case ..<0.34:
            return "Minor word fixes only — intention, fillers, near-homophones. Keeps your voice."
        case ..<0.67:
            return "Cleanup + light grammar and punctuation. Natural tone, still close to what you said."
        default:
            return "Full polish — grammar, smoother phrasing, more formal and polished prose."
        }
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
    
    /// Newest-first dictation history (capped).
    var dictationHistory: [DictationHistoryEntry] = [] {
        didSet {
            guard !isHydrating else { return }
            persistDictationHistory()
        }
    }
    
    static let maxHistoryEntries = 100
    
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
        static let aiPolish = "whisper67.aiPolish"
        static let aiPolishStrength = "whisper67.aiPolishStrength"
        static let openAIKey = "openai_api_key"
        static let groqKey = "groq_api_key"
        static let customWords = "whisper67.customWords"
        static let usageStats = "whisper67.usageStats"
        static let dictationHistory = "whisper67.dictationHistory"
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
        // Default ON; respect user toggle when previously set
        if defaults.object(forKey: Keys.autoPaste) == nil {
            autoPaste = true
        } else {
            autoPaste = defaults.bool(forKey: Keys.autoPaste)
        }
        
        // Default ON for Control PTT unless user previously turned it off
        if defaults.object(forKey: Keys.controlPTT) == nil {
            controlPushToTalkEnabled = true
        } else {
            controlPushToTalkEnabled = defaults.bool(forKey: Keys.controlPTT)
        }
        
        dictationStyle = DictationStyle.fromStored(defaults.string(forKey: Keys.dictationStyle))
        listModeEnabled = defaults.bool(forKey: Keys.listMode)
        
        // Default AI polish ON when unset (Wispr-like); needs Groq key at runtime
        if defaults.object(forKey: Keys.aiPolish) == nil {
            aiPolishEnabled = true
        } else {
            aiPolishEnabled = defaults.bool(forKey: Keys.aiPolish)
        }
        
        // Default strength ~0.35 (light–balanced): intention + light cleanup, not full rewrite
        if defaults.object(forKey: Keys.aiPolishStrength) == nil {
            aiPolishStrength = 0.35
        } else {
            aiPolishStrength = min(1, max(0, defaults.double(forKey: Keys.aiPolishStrength)))
        }
        
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
        
        if let data = defaults.data(forKey: Keys.dictationHistory),
           let history = try? JSONDecoder().decode([DictationHistoryEntry].self, from: data) {
            dictationHistory = history
        } else {
            dictationHistory = []
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
    
    /// Prompt hint for Whisper APIs to bias vocabulary (custom dictionary + built-ins).
    var dictionaryPrompt: String {
        IntentVocabulary.whisperBiasPrompt(userDictionary: customWords.map(\.word))
    }
    
    /// Full prompt sent to Whisper: style + optional list bias + dictionary intention.
    var transcriptionPrompt: String {
        var parts: [String] = [dictationStyle.whisperHint]
        if listModeEnabled {
            parts.append("If the speaker lists items, number them as 1. 2. 3. on separate lines.")
        }
        let dict = dictionaryPrompt
        if !dict.isEmpty { parts.append(dict) }
        return parts.joined(separator: " ")
    }
    
    /// Apply self-corrections + dictionary repair + style (no LLM).
    /// - Parameter forceList: only true when `ListDetector` says this utterance is a list.
    func formatTranscript(_ raw: String, forceList: Bool? = nil) -> String {
        var intended = SelfCorrection.apply(raw)
        intended = IntentVocabulary.localRepair(intended, userDictionary: customWords.map(\.word))
        let useList: Bool
        if let forceList {
            useList = forceList
        } else if listModeEnabled {
            useList = ListDetector.isLikelyList(intended)
        } else {
            useList = false
        }
        return TranscriptFormatter.format(intended, style: dictationStyle, listMode: useList)
    }
    
    var hasGroqKey: Bool {
        !groqKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// True when polish is enabled and a Groq key is present.
    var canRunAIPolish: Bool {
        aiPolishEnabled && hasGroqKey
    }
    
    /// List mode + Groq available (OSS may format when detector says list).
    var canRunOSSList: Bool {
        listModeEnabled && hasGroqKey
    }
    
    var modeStatusLabel: String {
        var label = dictationStyle.displayName
        if listModeEnabled { label += " · Lists" }
        if canRunAIPolish {
            label += " · AI \(aiPolishStrengthLabel)"
        } else if aiPolishEnabled {
            label += " · AI needs Groq"
        }
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
        appendHistory(text: text, audioSeconds: audioSeconds)
    }
    
    func appendHistory(text: String, audioSeconds: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        var next = dictationHistory
        next.insert(
            DictationHistoryEntry(text: trimmed, audioSeconds: audioSeconds, provider: provider),
            at: 0
        )
        if next.count > Self.maxHistoryEntries {
            next = Array(next.prefix(Self.maxHistoryEntries))
        }
        dictationHistory = next
        persistDictationHistory()
    }
    
    func removeHistoryEntry(_ entry: DictationHistoryEntry) {
        var next = dictationHistory
        next.removeAll { $0.id == entry.id }
        dictationHistory = next
        persistDictationHistory()
    }
    
    func clearDictationHistory() {
        dictationHistory = []
        persistDictationHistory()
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
    
    private func persistDictationHistory() {
        do {
            let data = try JSONEncoder().encode(dictationHistory)
            UserDefaults.standard.set(data, forKey: Keys.dictationHistory)
            UserDefaults.standard.synchronize()
            print("💾 History saved (\(dictationHistory.count) entries)")
        } catch {
            print("❌ History save failed: \(error)")
        }
    }
}
