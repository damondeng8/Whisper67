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
        case .raw: return text
        case .casual: return applyCasual(text)
        case .normal: return applyNormal(text)
        case .formal: return applyFormal(text)
        }
    }
    
    /// Casual / chat: mostly lowercase, keep contractions & informal voice.
    /// Times like `3:30pm` / `3pm` are protected so `:` is never turned into `,`.
    private static func applyCasual(_ text: String) -> String {
        withProtectedTimes(text) { body in
            var t = body
            for ch in ["!", "?", ";"] {
                t = t.replacingOccurrences(of: ch, with: ",")
            }
            // Do not replace bare ":" here — times are masked; any leftover ":" is clause-ish → comma
            t = t.replacingOccurrences(of: ":", with: ",")
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
    }
    
    /// Normal: commas for pauses, no periods / ! / ?
    /// Times kept intact (`3pm`, `3:30pm`) — never `3,00`.
    private static func applyNormal(_ text: String) -> String {
        withProtectedTimes(text) { body in
            var t = body
            
            let toComma = ["!", "?", ";", "—", "–", "…", ".", ":"]
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
    }
    
    /// Mask clock times, run transform, unmask — so style punctuation never mangles them.
    private static func withProtectedTimes(_ text: String, transform: (String) -> String) -> String {
        // 3:30pm | 3pm | 3:00 | 12:00am | 3,00 (broken form we may still see)
        let pattern = #"(?i)\b\d{1,2}:\d{2}\s*(?:a\.?m\.?|p\.?m\.?)?\b|\b\d{1,2}\s*(?:a\.?m\.?|p\.?m\.?)\b|\b\d{1,2},\d{2}\s*(?:a\.?m\.?|p\.?m\.?)?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return TimeNormalizer.normalize(transform(text))
        }
        
        var work = text
        var tokens: [String] = []
        let matches = regex.matches(in: work, range: NSRange(work.startIndex..., in: work))
        
        // Replace from the end so ranges stay valid
        for match in matches.enumerated().reversed() {
            let (idx, m) = match
            let ns = work as NSString
            let token = ns.substring(with: m.range)
            let key = "ZZTIME\(idx)ZZ"
            // Ensure tokens array size
            while tokens.count <= idx { tokens.append("") }
            tokens[idx] = token
            work = ns.replacingCharacters(in: m.range, with: key)
        }
        
        var result = transform(work)
        // Casual lowercases placeholders → zztime0zz
        for (i, token) in tokens.enumerated() where !token.isEmpty {
            let upper = "ZZTIME\(i)ZZ"
            let lower = "zztime\(i)zz"
            result = result.replacingOccurrences(of: upper, with: token)
            result = result.replacingOccurrences(of: lower, with: token)
        }
        // Fix any times that style still broke (e.g. 3,00)
        return TimeNormalizer.normalize(result)
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
        // Keep greeting / lead-in as prose above the numbered items
        let (intro, body) = splitIntroAndListBody(text)
        let source = body.isEmpty ? text : body
        
        let items = splitListItems(source)
        guard items.count >= 2 else {
            if looksLikeExplicitList(text) {
                let cleaned = stripListMarkers(source.isEmpty ? text : source)
                let line = cleaned.isEmpty ? text : "1. \(cleaned)"
                return mergeIntro(intro, list: line)
            }
            return text
        }
        
        let list = items.enumerated().map { idx, item in
            let cleaned = stripListMarkers(item)
            return "\(idx + 1). \(cleaned)"
        }.joined(separator: "\n")
        
        return mergeIntro(intro, list: list)
    }
    
    /// "hey John I need three things first milk second eggs" → intro + "first milk second eggs"
    private static func splitIntroAndListBody(_ text: String) -> (intro: String, body: String) {
        let patterns = [
            #"(?i)\bnumber\s+(one|1|two|2)\b"#,
            #"(?i)\b(firstly|first)\b"#,
            #"(?i)(?:^|\n)\s*\d+[.)]\s+"#
        ]
        
        var earliest: Range<String.Index>?
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let swiftRange = Range(match.range, in: text) else { continue }
            // Only treat as list body start if there is real content before it
            if swiftRange.lowerBound > text.startIndex {
                if earliest == nil || swiftRange.lowerBound < earliest!.lowerBound {
                    earliest = swiftRange
                }
            }
        }
        
        guard let start = earliest else { return ("", text) }
        
        var intro = String(text[..<start.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop trailing conjunctions left hanging before the list
        for suffix in [" and", " then", ":", ",", " —", " –", " -"] {
            if intro.lowercased().hasSuffix(suffix) {
                intro = String(intro.dropLast(suffix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        let body = String(text[start.lowerBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Intro must look like prose (not already an item); require a few letters
        guard intro.count >= 3, intro.split(whereSeparator: { $0.isWhitespace }).count >= 1 else {
            return ("", text)
        }
        
        return (intro, body)
    }
    
    private static func mergeIntro(_ intro: String, list: String) -> String {
        let trimmedIntro = intro.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIntro.isEmpty else { return list }
        // Ensure intro ends cleanly before list
        var head = trimmedIntro
        if let last = head.last, last.isLetter || last == "'" || last == "’" {
            // No forced period — style pass may adjust
        }
        return head + "\n" + list
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
