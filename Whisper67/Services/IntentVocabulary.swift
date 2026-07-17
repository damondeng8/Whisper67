import Foundation

/// User dictionary only — preferred spellings for Whisper bias, local repair, and OSS intention.
/// No built-in product names; the user adds every term they care about.
enum IntentVocabulary {
    
    // MARK: - User terms only
    
    /// Deduped user dictionary (order preserved, first wins).
    static func preferredTerms(userDictionary: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for w in userDictionary.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            let key = w.lowercased()
            if seen.insert(key).inserted {
                out.append(w)
            }
        }
        return out
    }
    
    /// Compact Whisper prompt bias. Empty when dictionary is empty.
    static func whisperBiasPrompt(userDictionary: [String]) -> String {
        let terms = preferredTerms(userDictionary: userDictionary)
        guard !terms.isEmpty else { return "" }
        let list = terms.prefix(40).joined(separator: ", ")
        return "Prefer exact spellings: \(list)."
    }
    
    /// Bullet list for the OSS intention prompt. Empty when no user terms.
    static func intentionBlock(userDictionary: [String]) -> String {
        let terms = preferredTerms(userDictionary: userDictionary)
        guard !terms.isEmpty else { return "" }
        
        var lines: [String] = [
            "INTENTION / VOCABULARY (user dictionary only):",
            "The speaker defined preferred spellings below. When audio could match a preferred term or a similar-sounding wrong word, use the preferred spelling.",
            "Homophones and near-homophones: pick the dictionary term that fits context.",
            "Do not invent jargon. Only apply fixes when a preferred term is a plausible match.",
            "",
            "Preferred terms (exact spellings):"
        ]
        for t in terms.prefix(60) {
            lines.append("- \(t)")
        }
        lines.append("")
        lines.append("If a preferred multi-word phrase is split across wrong words, rejoin it to the dictionary form.")
        lines.append("")
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Local fast repair (user dictionary only)
    
    /// Near-miss repair for user terms (hyphen/space variants + light fuzzy tokens).
    static func localRepair(_ text: String, userDictionary: [String]) -> String {
        let preferred = preferredTerms(userDictionary: userDictionary)
        guard !preferred.isEmpty else { return text }
        
        var result = text
        let sortedPreferred = preferred.sorted { $0.count > $1.count }
        
        for pref in sortedPreferred {
            let prefLower = pref.lowercased()
            let variants = autoVariants(for: pref)
            let unique = Array(Set(variants.map { $0.lowercased() }))
                .sorted { $0.count > $1.count }
            
            for variant in unique {
                result = replaceWholePhrase(in: result, match: variant, with: pref)
                _ = prefLower // casing normalized via `with: pref`
            }
        }
        
        let singleToken = sortedPreferred.filter { term in
            !term.contains(" ") && term.count >= 4
        }
        result = fuzzyDictionaryTokens(result, preferred: singleToken)
        
        return result
    }
    
    // MARK: - Helpers
    
    /// Hyphen / space / concatenated forms of a user term (no hard-coded product list).
    private static func autoVariants(for term: String) -> [String] {
        var v: [String] = [term]
        let lower = term.lowercased()
        v.append(lower)
        v.append(lower.replacingOccurrences(of: "-", with: " "))
        v.append(lower.replacingOccurrences(of: " ", with: "-"))
        v.append(lower.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: ""))
        return v
    }
    
    private static func replaceWholePhrase(in text: String, match: String, with replacement: String) -> String {
        guard !match.isEmpty else { return text }
        let pattern = "(?i)(?<![A-Za-z0-9])\(NSRegularExpression.escapedPattern(for: match))(?![A-Za-z0-9])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
    
    private static func fuzzyDictionaryTokens(_ text: String, preferred: [String]) -> String {
        guard !preferred.isEmpty else { return text }
        let parts = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty else { return text }
        
        let mapped = parts.map { token -> String in
            let stripped = token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard stripped.count >= 4 else { return token }
            let lower = stripped.lowercased()
            var best: String?
            var bestDist = Int.max
            for pref in preferred {
                let p = pref.lowercased()
                guard abs(p.count - lower.count) <= 2 else { continue }
                let d = levenshtein(lower, p)
                let maxD = p.count >= 7 ? 2 : 1
                if d > 0, d <= maxD, d < bestDist {
                    bestDist = d
                    best = pref
                }
            }
            guard let best else { return token }
            if let r = token.range(of: stripped) {
                return token.replacingCharacters(in: r, with: best)
            }
            return best
        }
        return mapped.joined(separator: " ")
    }
    
    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        var cur = Array(repeating: 0, count: n + 1)
        for i in 1...m {
            cur[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = cur
        }
        return prev[n]
    }
}
