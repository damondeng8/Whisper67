import Foundation

/// Decides whether dictation is *actually* a list vs normal prose/intro.
/// Auto-list mode only formats as 1. 2. 3. when this says yes.
enum ListDetector {
    
    struct Result: Sendable {
        /// True → numbered list is appropriate.
        let isLikelyList: Bool
        /// 0…10 rough confidence for logging / prompts.
        let score: Int
        /// Short reason for OSS / debug.
        let reason: String
    }
    
    static func analyze(_ raw: String) -> Result {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return Result(isLikelyList: false, score: 0, reason: "empty")
        }
        
        let lower = text.lowercased()
        var score = 0
        var reasons: [String] = []
        
        // --- Strong positive signals ---
        let ordinalPairs: [(String, String, Int)] = [
            ("first", "second", 4),
            ("firstly", "secondly", 4),
            ("number one", "number two", 4),
            ("number 1", "number 2", 4),
            ("1.", "2.", 3),
            ("1)", "2)", 3)
        ]
        for (a, b, pts) in ordinalPairs {
            if lower.contains(a) && lower.contains(b) {
                score += pts
                reasons.append("ordinal pair \(a)/\(b)")
            }
        }
        
        // third/fourth without second still helps a bit if first present
        if lower.contains("first") && (lower.contains("third") || lower.contains("fourth")) {
            score += 2
            reasons.append("first+later ordinal")
        }
        
        // Explicit list framing
        let frames = [
            "the following", "as follows", "these things", "three things", "a few things",
            "several things", "the items", "bullet", "checklist", "to-do", "todo",
            "my list", "shopping list", "action items"
        ]
        for f in frames where lower.contains(f) {
            score += 2
            reasons.append("frame:\(f)")
            break
        }
        
        // Step language: need 2+ distinct step cues (next/then/also/finally/plus)
        let stepWords = [" next ", " then ", " also ", " finally ", " plus ", " after that ", " and then "]
        let padded = " \(lower) "
        var stepHits = 0
        for w in stepWords {
            if padded.contains(w) { stepHits += 1 }
        }
        if stepHits >= 2 {
            score += 3
            reasons.append("step cues×\(stepHits)")
        } else if stepHits == 1 {
            score += 0 // single "then" in prose is normal
        }
        
        // Already multi-line short items
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count >= 3, lines.allSatisfy({ $0.split(separator: " ").count <= 12 }) {
            score += 2
            reasons.append("multiline short items")
        }
        
        // Spoken "number three" etc. count
        if let re = try? NSRegularExpression(pattern: #"(?i)\bnumber\s+(\d+|one|two|three|four|five|six|seven|eight|nine|ten)\b"#) {
            let n = re.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            if n >= 2 {
                score += 3
                reasons.append("number N ×\(n)")
            }
        }
        
        // --- Negative signals (normal prose / intros) ---
        let greetingStarts = ["hey ", "hi ", "hello ", "dear ", "good morning", "good afternoon", "good evening"]
        let startsWithGreeting = greetingStarts.contains { lower.hasPrefix($0) }
            || lower.hasPrefix("yo ")
        if startsWithGreeting {
            score -= 2
            reasons.append("greeting opener")
        }
        
        // Single flowing sentence with "and" but no ordinals → not a list
        let hasOrdinalWord = ["first", "second", "third", "fourth", "fifth", "firstly", "secondly", "thirdly"]
            .contains { lower.contains($0) }
        let sentenceLike = text.filter { $0 == "." || $0 == "!" || $0 == "?" }.count <= 1
            && !lower.contains("\n")
        if sentenceLike && !hasOrdinalWord && stepHits < 2 {
            score -= 2
            reasons.append("single prose sentence")
        }
        
        // Very short utterances rarely need lists unless explicit
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        if words.count <= 6 && !hasOrdinalWord && stepHits < 2 {
            score -= 1
            reasons.append("very short")
        }
        
        // "I would like X" / "I need X" single request without enumeration
        if (lower.contains("i would like") || lower.contains("i'd like") || lower.contains("i want"))
            && !hasOrdinalWord && stepHits < 2 {
            score -= 2
            reasons.append("want/like request")
        }
        
        let isList = score >= 3
        let reason = reasons.isEmpty ? "no signals" : reasons.joined(separator: ", ")
        AppLog.debug("📋 ListDetector score=\(score) list=\(isList) — \(reason)")
        return Result(isLikelyList: isList, score: score, reason: reason)
    }
    
    static func isLikelyList(_ raw: String) -> Bool {
        analyze(raw).isLikelyList
    }
    
    /// True if text already looks like a numbered list (1. / 2. lines).
    static func looksLikeNumberedList(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { return false }
        let numbered = lines.filter { line in
            line.range(of: #"^\d+[.)]\s+\S"#, options: .regularExpression) != nil
        }
        return numbered.count >= 2
    }
    
    /// Undo a false numbered list → single prose paragraph (keep all words).
    static func demoteNumberedListToProse(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let stripped = lines.map { line -> String in
            if let r = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                return String(line[r.upperBound...])
            }
            return line
        }
        // Join with spaces; if a line already ends with punctuation keep flow
        var out = ""
        for (i, part) in stripped.enumerated() {
            if i == 0 {
                out = part
            } else if out.last == "." || out.last == "!" || out.last == "?" {
                out += " " + part
            } else if part.first?.isUppercase == true && part.count > 20 {
                out += ". " + part
            } else {
                out += " " + part
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
