import Foundation

/// Post-Whisper LLM polish + intention check.
/// Strength 0…1: light word tweaks → full grammar / formal rewrite.
/// Uses Groq `openai/gpt-oss-20b` (cheap + fast).
enum TranscriptCleanupService {
    
    static let modelID = "openai/gpt-oss-20b"
    
    private static let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    
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
        
        // Always run local intention repair first (instant, no API)
        let locallyFixed = IntentVocabulary.localRepair(text, userDictionary: dictionaryWords)
        
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
                print("📋 Demoting false numbered list → prose")
                trimmed = ListDetector.demoteNumberedListToProse(trimmed)
            }
            
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
        request.timeoutInterval = 12
        
        let userContent = buildUserMessage(
            raw: raw,
            style: style,
            listModeEnabled: listModeEnabled,
            listLikely: listLikely,
            dictionaryWords: dictionaryWords,
            strength: strength
        )
        
        // Stronger polish may produce slightly longer prose
        let expand = 1.0 + strength * 1.2
        let maxOut = min(2048, max(128, Int(Double(raw.count) * expand * 2)))
        
        // Light = deterministic; strong = a bit more room to rephrase
        let temperature = 0.08 + strength * 0.35
        
        let body: [String: Any] = [
            "model": modelID,
            "messages": [
                ["role": "user", "content": userContent]
            ],
            "temperature": temperature,
            "max_completion_tokens": maxOut,
            "top_p": 0.9,
            "stream": false,
            "reasoning_effort": "low",
            "include_reasoning": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
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
                "- Fix wrong words / near-homophones using the user dictionary when provided.",
                "- Apply self-corrections (\"Tuesday wait no Friday\" → Friday).",
                "- Remove pure noise fillers only (um, uh) — never names or greetings.",
                "- Light capitalization and end punctuation if missing.",
                "- Do NOT rephrase, formalize, summarize, or shorten.",
                "- Do NOT remove \"hey/hi/hello + name\" or any addressed line.",
                "- Keep sentence structure almost identical to the transcript.",
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
        
        rules.append(contentsOf: [
            "You clean speech-to-text for paste. Intensity: \(tier).",
            "Output ONLY the final text — no quotes, markdown fences, or commentary.",
            "Do not translate.",
            "",
            "══════════════════════════════════════",
            "CONTENT PRESERVATION (HIGHEST PRIORITY)",
            "══════════════════════════════════════",
            "- Keep EVERY meaningful part: greetings, names, openers, closers, asides.",
            "- NEVER drop \"Hey John\", \"Hi Sarah\", \"Dear team\", or similar addresses.",
            "- NEVER delete whole clauses or turn a full sentence into only nouns.",
            "- Only remove pure fillers (um, uh) and false starts the speaker replaced.",
            "- If unsure whether something is filler vs content, KEEP it.",
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
        
        // Reject aggressive deletion (e.g. dropped "Hey John" / whole clauses)
        let origWords = significantWords(original)
        let cleanWords = significantWords(cleaned)
        if !origWords.isEmpty {
            let kept = origWords.filter { cleanWords.contains($0) }.count
            let keepRatio = Double(kept) / Double(origWords.count)
            // At light strength require ~70% of content words; strong allows a bit more rephrase
            let minKeep = strength < 0.34 ? 0.70 : (strength < 0.67 ? 0.55 : 0.45)
            if keepRatio < minKeep {
                print("⚠️ Content keep ratio \(String(format: "%.2f", keepRatio)) < \(minKeep)")
                return true
            }
            // Openers (Hey/John/…) — at light/balanced, reject if first real word vanished
            if strength < 0.67,
               let first = origWords.first,
               first.count >= 3,
               !cleanWords.contains(first) {
                print("⚠️ Leading content word dropped: \(first)")
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
