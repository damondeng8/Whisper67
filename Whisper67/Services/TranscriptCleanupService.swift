import Foundation

/// Post-Whisper LLM polish + intention check.
/// Strength 0…1: light word tweaks → full grammar / formal rewrite.
/// Uses Groq `llama-3.1-8b-instant` — very fast, no reasoning delay (gpt-oss was timing out).
enum TranscriptCleanupService {
    
    /// Instant model on Groq (~ms tokens). Avoid reasoning models here — they blow past request timeouts.
    static let modelID = "llama-3.1-8b-instant"
    
    private static let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    
    /// Dedicated session: short request timeout, fail open to local cleanup.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
    
    private static let skipMarkers = [
        "No speech detected", "Recording too short", "No audio detected",
        "Transcription failed", "No transcription available", "Add an API key"
    ]
    
    // MARK: - Public
    
    /// Returns polished text, or `raw` unchanged on skip / failure (never blocks paste).
    /// - Parameter listModeEnabled: User toggle (smart list *allowed*).
    /// - Parameter listLikely: Pre-detector says this utterance is actually a list.
    /// - Parameter strength: 0 = lightest (words only), 1 = strongest (grammar + formal polish).
    static func polish(
        _ raw: String,
        style: DictationStyle,
        listModeEnabled: Bool,
        listLikely: Bool,
        dictionaryWords: [String],
        groqAPIKey: String,
        strength: Double = 0.35
    ) async -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return raw }
        
        if skipMarkers.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
            return raw
        }
        
        let intensity = min(1, max(0, strength))
        
        // Local passes first: self-corrections ("Thursday no Friday") + dictionary
        var locallyFixed = SelfCorrection.apply(text)
        locallyFixed = IntentVocabulary.localRepair(locallyFixed, userDictionary: dictionaryWords)
        
        let key = groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return locallyFixed }
        
        let wordCount = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        
        if wordCount <= 1,
           IntentVocabulary.preferredTerms(userDictionary: dictionaryWords)
            .allSatisfy({ !text.localizedCaseInsensitiveContains($0.replacingOccurrences(of: "-", with: " "))
                && !text.localizedCaseInsensitiveContains($0) }) {
            return locallyFixed
        }
        
        do {
            let cleaned = try await callGroq(
                raw: locallyFixed,
                style: style,
                listModeEnabled: listModeEnabled,
                listLikely: listLikely,
                dictionaryWords: dictionaryWords,
                strength: intensity,
                apiKey: key
            )
            var trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return locallyFixed }
            
            if looksLikeBadOutput(trimmed, original: text, strength: intensity) {
                print("⚠️ AI polish rejected (dropped/expanded content) — using local repair")
                return locallyFixed
            }
            
            // Hard guard: detector said prose → never keep a false numbered list
            if listModeEnabled && !listLikely && ListDetector.looksLikeNumberedList(trimmed) {
                AppLog.debug("📋 Demoting false numbered list → prose")
                trimmed = ListDetector.demoteNumberedListToProse(trimmed)
            }
            
            // Re-apply self-corrections + dictionary after OSS
            trimmed = SelfCorrection.apply(trimmed)
            trimmed = IntentVocabulary.localRepair(trimmed, userDictionary: dictionaryWords)
            
            let outWords = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            print("✨ OSS polish strength=\(String(format: "%.2f", intensity)) listLikely=\(listLikely) (\(wordCount) → \(outWords) words)")
            return trimmed
        } catch {
            print("⚠️ AI polish failed (using local intention): \(error.localizedDescription)")
            return locallyFixed
        }
    }
    
    // MARK: - Groq chat
    
    private static func callGroq(
        raw: String,
        style: DictationStyle,
        listModeEnabled: Bool,
        listLikely: Bool,
        dictionaryWords: [String],
        strength: Double,
        apiKey: String
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Fast fail — local SelfCorrection already ran; do not hang the whole dictation
        request.timeoutInterval = 15
        
        let userContent = buildUserMessage(
            raw: raw,
            style: style,
            listModeEnabled: listModeEnabled,
            listLikely: listLikely,
            dictionaryWords: dictionaryWords,
            strength: strength
        )
        
        // Tight cap: polish should not generate essays
        let maxOut = min(600, max(64, raw.count + 80))
        let temperature = 0.1 + strength * 0.25
        
        let body: [String: Any] = [
            "model": modelID,
            "messages": [
                ["role": "user", "content": userContent]
            ],
            "temperature": temperature,
            "max_completion_tokens": maxOut,
            "top_p": 0.9,
            "stream": false
            // No reasoning_effort — not a reasoning model; keeps latency low
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CleanupError.badResponse
        }
        
        if http.statusCode < 200 || http.statusCode >= 300 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }?
                .flatMap { $0["message"] as? String }
            ?? String(data: data, encoding: .utf8)?.prefix(180).description
            ?? "HTTP \(http.statusCode)"
            throw CleanupError.http(http.statusCode, msg)
        }
        
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw CleanupError.badResponse
        }
        
        return stripArtifacts(content)
    }
    
    // MARK: - Prompt by strength
    
    private static func buildUserMessage(
        raw: String,
        style: DictationStyle,
        listModeEnabled: Bool,
        listLikely: Bool,
        dictionaryWords: [String],
        strength: Double
    ) -> String {
        var rules: [String] = []
        
        let tier: String
        let tierRules: [String]
        switch strength {
        case ..<0.34:
            tier = "LIGHT (\(Int(strength * 100))%)"
            tierRules = [
                "INTENSITY: LIGHT — minimal changes only.",
                "- ALWAYS apply self-corrections (final intent only) — see SELF-CORRECTIONS above.",
                "- Fix wrong words / near-homophones using the user dictionary when provided.",
                "- Normalize times like \"3 30pm\" → \"3:30pm\".",
                "- Remove pure noise fillers only (um, uh) — never names or greetings.",
                "- Light capitalization and end punctuation if missing.",
                "- Do NOT formalize, summarize, or invent content.",
                "- Do NOT remove \"hey/hi/hello + name\" unless the speaker corrected it.",
            ]
        case ..<0.67:
            tier = "BALANCED (\(Int(strength * 100))%)"
            tierRules = [
                "INTENSITY: BALANCED — clean dictation, keep natural voice.",
                "- Fix intention / vocabulary confusions and self-corrections.",
                "- Remove fillers only when pure filler — keep all real words and openers.",
                "- Fix clear grammar slips and add natural punctuation.",
                "- Do NOT summarize or drop \"Hey John…\" style addresses.",
                "- Do NOT invent content or change meaning.",
                "- Stay close to what was said.",
            ]
        default:
            tier = "STRONG (\(Int(strength * 100))%)"
            tierRules = [
                "INTENSITY: STRONG — polish clarity and grammar, same facts.",
                "- Fix intention / vocabulary and self-corrections.",
                "- Remove fillers and false starts only — never drop greetings or names.",
                "- Fix grammar and improve flow; every original idea must remain.",
                "- Do NOT summarize into fewer points than the speaker made.",
                "- Names, numbers, URLs, and code must stay exact.",
            ]
        }
        
        // Compact prompt = faster completion (was timing out with huge prompts + reasoning models)
        rules.append(contentsOf: [
            "Clean this speech-to-text for paste. Intensity: \(tier). Output ONLY the cleaned text.",
            "Self-corrections: keep FINAL intent only. \"Thursday no actually Friday\" → Friday. \"2 no wait 3pm\" → 3pm.",
            "Times: use H:MM am/pm. \"3 30pm\" / \"3, 30 pm\" / \"three thirty\" → 3:30pm. half past 3 → 3:30. 3 o'clock → 3:00.",
            "Keep greetings/names. Remove um/uh fillers. Do not invent content or translate.",
            ""
        ])
        
        // Dynamic list decision from local detector — model must obey
        if !listModeEnabled {
            rules.append("LISTING: OFF. Output normal paragraphs only. Never use numbered lines (1. 2. 3.).")
            rules.append("")
        } else if listLikely {
            rules.append(contentsOf: Self.listYesInstructions)
            rules.append("")
        } else {
            rules.append(contentsOf: Self.listNoInstructions)
            rules.append("")
        }
        
        rules.append(contentsOf: tierRules)
        rules.append("")
        rules.append(IntentVocabulary.intentionBlock(userDictionary: dictionaryWords))
        
        // Style is mandatory output shape (local formatter also enforces after)
        switch style {
        case .raw:
            rules.append(contentsOf: [
                "WRITING STYLE — RAW (required):",
                "- Keep the transcript as close to the original as possible.",
                "- Only fix clear transcription errors; do not restyle punctuation or tone.",
                ""
            ])
        case .casual:
            rules.append(contentsOf: [
                "WRITING STYLE — CASUAL (required):",
                "- Output mostly lowercase, like casual texting/chat.",
                "- Keep contractions (i'm, don't, we'll) and informal wording.",
                "- Do NOT formalize. Do NOT expand contractions.",
                "- Prefer soft commas if needed; avoid formal periods/exclamation.",
                "- Keep the speaker's casual voice and slang.",
                ""
            ])
        case .normal:
            rules.append(contentsOf: [
                "WRITING STYLE — NORMAL (required):",
                "- Use commas for pauses and clauses.",
                "- Do NOT use periods, question marks, or exclamation points.",
                "- Capitalize only the start of the whole text (and list intros if any).",
                "- Flow as continuous spoken prose joined with commas, not full sentences.",
                "- Example: \"Hey John, I would like some food, then we can go\"",
                ""
            ])
        case .formal:
            rules.append(contentsOf: [
                "WRITING STYLE — FORMAL (required):",
                "- Full formal written English: proper capitalization every sentence.",
                "- Complete punctuation: periods, commas, question marks as appropriate.",
                "- Expand casual contractions when natural (don't → do not).",
                "- Polished professional prose — still same meaning, no invented content.",
                ""
            ])
        }
        
        rules.append("Raw transcript:")
        rules.append(raw)
        
        return rules.joined(separator: "\n")
    }
    
    /// Detector said: this IS a list.
    private static var listYesInstructions: [String] {
        [
            "══════════════════════════════════════",
            "LISTING: YES (detector found list signals)",
            "══════════════════════════════════════",
            "Format discrete items as a numbered list.",
            "Keep any greeting or lead-in ABOVE the list as normal prose.",
            "Format:",
            "1. First item",
            "2. Second item",
            "(digit, period, space — no bullets)",
            "",
            "Example — pure list:",
            "Input: first buy milk second get eggs third pick up bread",
            "Output:",
            "1. Buy milk",
            "2. Get eggs",
            "3. Pick up bread",
            "",
            "Example — intro + list:",
            "Input: hey John I need three things first milk second eggs third bread",
            "Output:",
            "Hey John, I need three things:",
            "1. Milk",
            "2. Eggs",
            "3. Bread",
            ""
        ]
    }
    
    /// Detector said: this is NOT a list (intro / normal sentence).
    private static var listNoInstructions: [String] {
        [
            "══════════════════════════════════════",
            "LISTING: NO (detector: normal prose / intro)",
            "══════════════════════════════════════",
            "CRITICAL: Do NOT format as a numbered list. Do NOT output lines starting with 1. 2. 3.",
            "Output a normal sentence or paragraph only.",
            "Keep greetings and full wording.",
            "",
            "Examples (all stay as prose — no lists):",
            "Input: hey John I would like some food",
            "Output: Hey John, I would like some food.",
            "",
            "Input: I need milk and eggs and bread from the store",
            "Output: I need milk and eggs and bread from the store.",
            "",
            "Input: yo what's up my name is Zach",
            "Output: Yo, what's up? My name is Zach.",
            ""
        ]
    }
    
    // MARK: - Sanitizers
    
    private static func stripArtifacts(_ content: String) -> String {
        var t = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let regex = try? NSRegularExpression(
            pattern: #"(?s)<think>.*?</think>"#,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(t.startIndex..., in: t)
            t = regex.stringByReplacingMatches(in: t, range: range, withTemplate: "")
        }
        
        if t.hasPrefix("```"), let end = t.range(of: "```", options: [], range: t.index(after: t.startIndex)..<t.endIndex) {
            var inner = String(t[t.index(t.startIndex, offsetBy: 3)..<end.lowerBound])
            if let nl = inner.firstIndex(of: "\n") {
                let first = String(inner[..<nl])
                if first.count < 20, first.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) {
                    inner = String(inner[inner.index(after: nl)...])
                }
            }
            t = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let preambles = [
            "Here is the cleaned text:",
            "Here's the cleaned text:",
            "Cleaned transcript:",
            "Cleaned text:",
            "Here is the corrected text:",
            "Corrected:"
        ]
        for p in preambles {
            if t.lowercased().hasPrefix(p.lowercased()) {
                t = String(t.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func looksLikeBadOutput(_ cleaned: String, original: String, strength: Double) -> Bool {
        // Reject runaway expansion
        let maxFactor = 2.0 + strength * 2.5
        let maxExtra = 200 + Int(strength * 400)
        if cleaned.count > max(Int(Double(original.count) * maxFactor), original.count + maxExtra) {
            return true
        }
        
        // Self-corrections legitimately drop superseded words — use looser keep ratio
        // when the raw transcript has correction markers.
        let hasCorrectionCue = original.range(
            of: #"(?i)\b(no|nope|wait|actually|i mean|scratch that)\b"#,
            options: .regularExpression
        ) != nil
        
        let origWords = significantWords(original)
        let cleanWords = significantWords(cleaned)
        if !origWords.isEmpty {
            let kept = origWords.filter { cleanWords.contains($0) }.count
            let keepRatio = Double(kept) / Double(origWords.count)
            let minKeep: Double
            if hasCorrectionCue {
                minKeep = 0.35 // allow dropping "Thursday" etc.
            } else {
                minKeep = strength < 0.34 ? 0.70 : (strength < 0.67 ? 0.55 : 0.45)
            }
            if keepRatio < minKeep {
                AppLog.debug("⚠️ Content keep ratio \(String(format: "%.2f", keepRatio)) < \(minKeep)")
                return true
            }
            // Openers — only enforce when no correction cue (correction might rewrite start)
            if !hasCorrectionCue,
               strength < 0.67,
               let first = origWords.first,
               first.count >= 3,
               !cleanWords.contains(first) {
                AppLog.debug("⚠️ Leading content word dropped: \(first)")
                return true
            }
        }
        
        let lower = cleaned.lowercased()
        if lower.hasPrefix("i'm sorry") || lower.hasPrefix("i cannot") || lower.hasPrefix("as an ai") {
            return true
        }
        if lower.contains("<think>") {
            return true
        }
        return false
    }
    
    /// Content words for deletion detection (lowercased, skip tiny fillers).
    private static func significantWords(_ text: String) -> [String] {
        let fillers: Set<String> = [
            "um", "uh", "uhh", "erm", "like", "you", "know", "basically",
            "so", "well", "yeah", "ok", "okay", "a", "an", "the", "to", "of", "and", "or"
        ]
        return text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !fillers.contains($0) }
    }
    
    enum CleanupError: LocalizedError {
        case badResponse
        case http(Int, String)
        
        var errorDescription: String? {
            switch self {
            case .badResponse: return "Invalid cleanup response"
            case .http(let code, let msg): return "Cleanup API \(code): \(msg)"
            }
        }
    }
}
