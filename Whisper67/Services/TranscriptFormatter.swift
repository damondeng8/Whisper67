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
        
        // Skip error / system strings
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
        
        switch style {
        case .casual:
            text = applyCasual(text)
        case .formal:
            text = applyFormal(text)
        case .periodsOnly:
            text = applyPeriodsOnly(text)
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Style
    
    /// Natural spoken tone — light cleanup only.
    private static func applyCasual(_ text: String) -> String {
        var t = text
        // Soft sentence starts
        t = capitalizeSentenceStarts(t, forceAll: false)
        // Collapse double spaces
        t = cleanupWhitespace(t)
        return t
    }
    
    /// Polished prose: sentence case, proper terminal punctuation.
    private static func applyFormal(_ text: String) -> String {
        var t = text
        t = expandCasualContractions(t)
        t = capitalizeSentenceStarts(t, forceAll: true)
        t = ensureSentencePunctuation(t)
        t = cleanupWhitespace(t)
        return t
    }
    
    /// Formal wording feel, but only periods as real punctuation (no , ! ? ; : —).
    private static func applyPeriodsOnly(_ text: String) -> String {
        var t = text
        
        // Turn common clause breaks into periods before stripping
        let swap: [(String, String)] = [
            ("!", "."), ("?", "."), (";", "."), (":", "."),
            ("—", "."), ("–", "."), ("…", ".")
        ]
        for (from, to) in swap {
            t = t.replacingOccurrences(of: from, with: to)
        }
        
        // Remove remaining fancy punctuation; keep letters, digits, spaces, periods, apostrophes in words
        var out = ""
        out.reserveCapacity(t.count)
        for ch in t {
            if ch.isLetter || ch.isNumber || ch == "." || ch == "'" || ch == "’" || ch == "\n" {
                out.append(ch)
            } else if ch.isWhitespace {
                out.append(" ")
            } else if ch == "," {
                // Commas → space (user wants mainly periods, not commas)
                out.append(" ")
            }
            // drop quotes, parens, etc.
        }
        
        t = cleanupWhitespace(out)
        // Collapse " . " and multiple periods
        while t.contains("..") { t = t.replacingOccurrences(of: "..", with: ".") }
        t = t.replacingOccurrences(of: " .", with: ".")
        t = capitalizeSentenceStarts(t, forceAll: true)
        t = ensureSentencePunctuation(t, periodOnly: true)
        t = cleanupWhitespace(t)
        return t
    }
    
    // MARK: - List mode
    
    /// Turn spoken list-like speech into:
    /// 1. item
    /// 2. item
    private static func formatAsList(_ text: String) -> String {
        let items = splitListItems(text)
        guard items.count >= 2 else {
            // Single item — still number if it looks list-y
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
        
        // Normalize spoken ordinals / separators into a pipe delimiter
        let patterns: [(String, String)] = [
            // "number one", "number 1"
            (#"(?i)\bnumber\s+(one|two|three|four|five|six|seven|eight|nine|ten|\d+)\b[.:]?\s*"#, "|"),
            // "first,", "secondly", "third:"
            (#"(?i)\b(firstly|secondly|thirdly|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\b[.:,]?\s*"#, "|"),
            // "1.", "2)" at line/item starts mid-string
            (#"(?<=^|[\n.])\s*\d+[.)]\s+"#, "|"),
            // "next,", "also,", "then,", "plus,"
            (#"(?i)\b(next|also|then|plus|another|and then)\b[.,]?\s+"#, "|"),
            // " and " between short phrases often means list (only if enough parts later)
            // applied carefully after other splits
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
        
        // If still one blob, try splitting on commas for list-like content
        if parts.count < 2 {
            let commaParts = text
                .components(separatedBy: ",")
                .map { cleanupWhitespace($0) }
                .filter { !$0.isEmpty }
            // Only treat as list if 3+ short-ish items
            if commaParts.count >= 3, commaParts.allSatisfy({ $0.split(separator: " ").count <= 12 }) {
                parts = commaParts
            }
        }
        
        // "A and B and C" style
        if parts.count < 2 {
            let andParts = splitOnStandaloneAnd(text)
            if andParts.count >= 3 {
                parts = andParts
            }
        }
        
        // Newlines already
        if parts.count < 2 {
            let lines = text
                .components(separatedBy: .newlines)
                .map { cleanupWhitespace($0) }
                .filter { !$0.isEmpty }
            if lines.count >= 2 { parts = lines }
        }
        
        return parts
    }
    
    private static func splitOnStandaloneAnd(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)\s+and\s+"#) else {
            return [text]
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 2 else { return [text] }
        
        var result: [String] = []
        var last = 0
        for m in matches {
            let piece = ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let cleaned = cleanupWhitespace(piece)
            if !cleaned.isEmpty { result.append(cleaned) }
            last = m.range.location + m.range.length
        }
        let tail = cleanupWhitespace(ns.substring(from: last))
        if !tail.isEmpty { result.append(tail) }
        return result
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
        // Capitalize first letter of list item
        if let first = s.first {
            s = String(first).uppercased() + s.dropFirst()
        }
        // Trim trailing list junk
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
        // Space before newline cleanup
        t = t.replacingOccurrences(of: " \n", with: "\n")
        t = t.replacingOccurrences(of: "\n ", with: "\n")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func capitalizeSentenceStarts(_ text: String, forceAll: Bool) -> String {
        // Split preserving list newlines
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
                // keep capitalizeNext
            } else if !forceAll {
                // casual: only first of line / after .!?
            }
        }
        // Always capitalize first letter of line
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
            // List items like "1. Foo" — leave as-is if short and no end punct needed? still period ok
            let last = s.last!
            let terminal: Set<Character> = periodOnly ? ["."] : [".", "!", "?"]
            if !terminal.contains(last), last.isLetter || last == "'" || last == "’" {
                s += "."
            }
            return s
        }.joined(separator: "\n")
    }
    
    private static func expandCasualContractions(_ text: String) -> String {
        // Light formal polish — only common expansions
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
