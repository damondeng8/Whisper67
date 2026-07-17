import Foundation

/// Post-processes raw Whisper text for the selected dictation style + list mode.
enum TranscriptFormatter {
    
    static func format(
        _ raw: String,
        style: DictationStyle,
        listMode: Bool
    ) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }
        
        let skip = [
            "No speech detected", "Recording too short", "No audio detected",
            "Transcription failed", "No transcription available", "Add an API key"
        ]
        if skip.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
            return text
        }
        
        text = cleanupWhitespace(text)
        
        if listMode {
            text = formatAsList(text)
        }
        
        // Style per line so "1. Item" markers survive Normal/Casual (never "1, Item")
        text = applyStylePreservingListMarkers(text, style: style)
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Style
    
    private static func applyStylePreservingListMarkers(_ text: String, style: DictationStyle) -> String {
        let lines = text.components(separatedBy: "\n")
        return lines.map { line in
            if let (prefix, body) = splitListMarker(line) {
                let styledBody = applyStyleToProse(body, style: style)
                return prefix + styledBody
            }
            return applyStyleToProse(line, style: style)
        }.joined(separator: "\n")
    }
    
    /// "1. " / "12) " prefix if present.
    private static func splitListMarker(_ line: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\d+[.)]\s+)(.*)$"#) else { return nil }
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges == 3 else { return nil }
        return (ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2)))
    }
    
    private static func applyStyleToProse(_ text: String, style: DictationStyle) -> String {
        switch style {
        case .casual: return applyCasual(text)
        case .normal: return applyNormal(text)
        case .formal: return applyFormal(text)
        }
    }
    
    /// Casual / chat: mostly lowercase, keep contractions & informal voice.
    private static func applyCasual(_ text: String) -> String {
        var t = text
        for ch in ["!", "?", ";", ":"] {
            t = t.replacingOccurrences(of: ch, with: ",")
        }
        t = t.replacingOccurrences(of: ". ", with: ", ")
        t = t.replacingOccurrences(of: ".", with: "")
        
        t = cleanupWhitespace(t)
        t = t.lowercased()
        
        while t.contains(",,") { t = t.replacingOccurrences(of: ",,", with: ",") }
        t = t.replacingOccurrences(of: " ,", with: ",")
        while t.hasSuffix(",") || t.hasSuffix(" ") {
            t = String(t.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return cleanupWhitespace(t)
    }
    
    /// Normal: commas for pauses, no periods / ! / ?
    private static func applyNormal(_ text: String) -> String {
        var t = text
        
        let toComma = ["!", "?", ";", ":", "—", "–", "…", "."]
        for ch in toComma {
            t = t.replacingOccurrences(of: ch, with: ",")
        }
        
        var out = ""
        out.reserveCapacity(t.count)
        for ch in t {
            if ch.isLetter || ch.isNumber || ch == "," || ch == "'" || ch == "’" || ch == "\n" {
                out.append(ch)
            } else if ch.isWhitespace {
                out.append(" ")
            }
        }
        
        t = cleanupWhitespace(out)
        while t.contains(",,") { t = t.replacingOccurrences(of: ",,", with: ",") }
        t = t.replacingOccurrences(of: " ,", with: ",")
        t = t.replacingOccurrences(of: ",", with: ", ")
        t = cleanupWhitespace(t)
        while t.contains(", ,") { t = t.replacingOccurrences(of: ", ,", with: ", ") }
        while t.hasSuffix(",") || t.hasSuffix(", ") {
            if t.hasSuffix(", ") { t = String(t.dropLast(2)) }
            else { t = String(t.dropLast()) }
            t = t.trimmingCharacters(in: .whitespaces)
        }
        
        t = capitalizeFirstLetter(t)
        return cleanupWhitespace(t)
    }
    
    /// Formal: full caps rules, periods, expanded contractions.
    private static func applyFormal(_ text: String) -> String {
        var t = text
        t = expandCasualContractions(t)
        t = capitalizeSentenceStarts(t, forceAll: true)
        t = ensureSentencePunctuation(t, periodOnly: false)
        t = cleanupWhitespace(t)
        return t
    }
    
    // MARK: - List mode
    
    private static func formatAsList(_ text: String) -> String {
        let items = splitListItems(text)
        guard items.count >= 2 else {
            if looksLikeExplicitList(text) {
                let cleaned = stripListMarkers(text)
                return cleaned.isEmpty ? text : "1. \(cleaned)"
            }
            return text
        }
        
        return items.enumerated().map { idx, item in
            let cleaned = stripListMarkers(item)
            return "\(idx + 1). \(cleaned)"
        }.joined(separator: "\n")
    }
    
    private static func looksLikeExplicitList(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = ["first ", "second ", "third ", "number one", "number 1", "item one", "bullet"]
        return markers.contains { lower.contains($0) }
    }
    
    private static func splitListItems(_ text: String) -> [String] {
        var working = text
        
        let patterns: [(String, String)] = [
            (#"(?i)\bnumber\s+(one|two|three|four|five|six|seven|eight|nine|ten|\d+)\b[.:]?\s*"#, "|"),
            (#"(?i)\b(firstly|secondly|thirdly|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\b[.:,]?\s*"#, "|"),
            (#"(?<=^|[\n.])\s*\d+[.)]\s+"#, "|"),
            (#"(?i)\b(next|also|then|plus|another|and then)\b[.,]?\s+"#, "|"),
        ]
        
        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(working.startIndex..., in: working)
                working = regex.stringByReplacingMatches(
                    in: working,
                    range: range,
                    withTemplate: replacement
                )
            }
        }
        
        var parts = working
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { cleanupWhitespace(String($0)) }
            .filter { !$0.isEmpty }
        
        if parts.count < 2 {
            let lines = text
                .components(separatedBy: .newlines)
                .map { cleanupWhitespace($0) }
                .filter { !$0.isEmpty }
            if lines.count >= 2 { parts = lines }
        }
        
        return parts
    }
    
    private static func stripListMarkers(_ item: String) -> String {
        var s = item
        let leading: [String] = [
            #"(?i)^(firstly|secondly|thirdly|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\s+"#,
            #"(?i)^number\s+(one|two|three|four|five|six|seven|eight|nine|ten|\d+)\s+"#,
            #"^\d+[.)]\s+"#,
            #"(?i)^(next|also|then|plus|another)\s+"#,
            #"(?i)^item\s+"#,
            #"(?i)^bullet\s+"#
        ]
        for p in leading {
            if let regex = try? NSRegularExpression(pattern: p) {
                let range = NSRange(s.startIndex..., in: s)
                s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
            }
        }
        s = cleanupWhitespace(s)
        if let first = s.first {
            s = String(first).uppercased() + s.dropFirst()
        }
        while s.hasSuffix(",") || s.hasSuffix(";") {
            s = String(s.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return s
    }
    
    // MARK: - Helpers
    
    private static func cleanupWhitespace(_ text: String) -> String {
        var t = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        t = t.replacingOccurrences(of: " \n", with: "\n")
        t = t.replacingOccurrences(of: "\n ", with: "\n")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func capitalizeFirstLetter(_ text: String) -> String {
        guard let idx = text.firstIndex(where: { $0.isLetter }) else { return text }
        var chars = Array(text)
        let i = text.distance(from: text.startIndex, to: idx)
        chars[i] = Character(String(chars[i]).uppercased())
        return String(chars)
    }
    
    private static func capitalizeSentenceStarts(_ text: String, forceAll: Bool) -> String {
        let lines = text.components(separatedBy: "\n")
        return lines.map { line -> String in
            capitalizeLine(line, forceAll: forceAll)
        }.joined(separator: "\n")
    }
    
    private static func capitalizeLine(_ line: String, forceAll: Bool) -> String {
        guard !line.isEmpty else { return line }
        var chars = Array(line)
        var capitalizeNext = true
        for i in chars.indices {
            let c = chars[i]
            if capitalizeNext, c.isLetter {
                chars[i] = Character(String(c).uppercased())
                capitalizeNext = false
            } else if c == "." || c == "!" || c == "?" || c == "\n" {
                capitalizeNext = true
            } else if c.isWhitespace {
                // keep
            } else if !forceAll {
            }
        }
        if let idx = chars.firstIndex(where: { $0.isLetter }) {
            chars[idx] = Character(String(chars[idx]).uppercased())
        }
        return String(chars)
    }
    
    private static func ensureSentencePunctuation(_ text: String, periodOnly: Bool = false) -> String {
        let lines = text.components(separatedBy: "\n")
        return lines.map { line in
            var s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { return s }
            let last = s.last!
            let terminal: Set<Character> = periodOnly ? ["."] : [".", "!", "?"]
            if !terminal.contains(last), last.isLetter || last == "'" || last == "’" {
                s += "."
            }
            return s
        }.joined(separator: "\n")
    }
    
    private static func expandCasualContractions(_ text: String) -> String {
        let pairs: [(String, String)] = [
            (#"(?i)\bdon't\b"#, "do not"),
            (#"(?i)\bdoesn't\b"#, "does not"),
            (#"(?i)\bdidn't\b"#, "did not"),
            (#"(?i)\bcan't\b"#, "cannot"),
            (#"(?i)\bwon't\b"#, "will not"),
            (#"(?i)\bisn't\b"#, "is not"),
            (#"(?i)\baren't\b"#, "are not"),
            (#"(?i)\bwasn't\b"#, "was not"),
            (#"(?i)\bweren't\b"#, "were not"),
            (#"(?i)\bhaven't\b"#, "have not"),
            (#"(?i)\bhasn't\b"#, "has not"),
            (#"(?i)\bhadn't\b"#, "had not"),
            (#"(?i)\bI'm\b"#, "I am"),
            (#"(?i)\byou're\b"#, "you are"),
            (#"(?i)\bwe're\b"#, "we are"),
            (#"(?i)\bthey're\b"#, "they are"),
            (#"(?i)\bit's\b"#, "it is"),
            (#"(?i)\bthat's\b"#, "that is"),
            (#"(?i)\bthere's\b"#, "there is"),
            (#"(?i)\bwhat's\b"#, "what is"),
            (#"(?i)\blet's\b"#, "let us"),
            (#"(?i)\bi've\b"#, "I have"),
            (#"(?i)\bwe've\b"#, "we have"),
            (#"(?i)\bthey've\b"#, "they have"),
            (#"(?i)\bi'll\b"#, "I will"),
            (#"(?i)\byou'll\b"#, "you will"),
            (#"(?i)\bwe'll\b"#, "we will"),
            (#"(?i)\bthey'll\b"#, "they will"),
            (#"(?i)\bi'd\b"#, "I would"),
            (#"(?i)\byou'd\b"#, "you would"),
            (#"(?i)\bwe'd\b"#, "we would"),
            (#"(?i)\bthey'd\b"#, "they would")
        ]
        var t = text
        for (pattern, replacement) in pairs {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(t.startIndex..., in: t)
                t = regex.stringByReplacingMatches(in: t, range: range, withTemplate: replacement)
            }
        }
        return t
    }
}
