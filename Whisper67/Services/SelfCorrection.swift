import Foundation

/// Mid-utterance spoken corrections + clock-time normalization.
///
/// "Thursday, no actually Friday at 3 30pm" → "Friday at 3:30pm"
enum SelfCorrection {
    
    static func apply(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        
        t = TimeNormalizer.normalize(t)
        
        for _ in 0..<6 {
            let next = applyOnce(t)
            if next == t { break }
            t = next
        }
        
        t = TimeNormalizer.normalize(t)
        t = cleanupArtifacts(t)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Correction pass
    
    private static func applyOnce(_ text: String) -> String {
        var t = text
        
        // Days: "Thursday no actually Friday"
        let days = "monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|tomorrow|tonight"
        t = replace(
            t,
            "(?i)\\b(\(days))\\b(?:\\s*[,;])?\\s+(?:uh\\s+|um\\s+|er\\s+)?(?:wait\\s+)?(?:no|nope|nah)(?:\\s*,)?\\s*(?:wait\\s+)?(?:actually\\s+|i\\s+mean\\s+)?\\b(\(days))\\b",
            "$2"
        )
        
        // Times / numbers: "2 no wait 3pm", "2:00 no 3:30"
        t = replace(
            t,
            #"(?i)\b(\d{1,2}(?::\d{2})?(?:am|pm|a\.m\.|p\.m\.)?)\s*(?:[,;])?\s+(?:uh\s+|um\s+)?(?:wait\s+)?(?:no|nope|nah)(?:\s*,)?\s*(?:wait\s+)?(?:actually\s+|i\s+mean\s+)?(\d{1,2}(?::\d{2})?(?:\s*(?:am|pm|a\.m\.|p\.m\.))?)\b"#,
            "$2"
        )
        
        // Single token: "John no actually Jane" / "Thursday no Friday"
        // Allows: uh/um before no; wait before or after no; actually / I mean
        t = replace(
            t,
            #"(?i)\b([\w']+)\s*(?:[,;])?\s+(?:uh\s+|um\s+|er\s+)?(?:wait\s+)?(?:no|nope|nah)(?:\s*,)?\s*(?:wait\s+)?(?:actually\s+|i\s+mean\s+)?([\w']+)\b"#,
            "$2"
        )
        
        // Multi-word when "actually" / "I mean" present
        t = replace(
            t,
            #"(?i)\b([\w']+(?:\s+[\w']+){0,2})\s*(?:[,;])?\s+(?:uh\s+|um\s+)?(?:wait\s+)?(?:no|nope)(?:\s*,)?\s+(?:actually\s+|i\s+mean\s+)([\w']+(?:\s+[\w']+){0,2})\b"#,
            "$2"
        )
        
        // "I mean Friday" after a word
        t = replace(
            t,
            #"(?i)\b([\w']+)\s*(?:[,;])?\s+i\s+mean\s+([\w']+)\b"#,
            "$2"
        )
        
        // Strip leftover correction debris
        t = replace(t, #"(?i)\bwait\s*,?\s*no(?:\s*,)?\s*(?:actually\s+)?"#, "")
        t = replace(t, #"(?i)(?:\s*[,;])?\s*\bno(?:\s*,)?\s+actually\b\s*"#, " ")
        t = replace(t, #"(?i)\b(?:scratch that|forget that|ignore that|correction)\b[,:]?\s*"#, "")
        t = replace(t, #"(?i)\s+\bno\s+wait\b\s+"#, " ")
        
        return t
    }
    
    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
    
    private static func cleanupArtifacts(_ text: String) -> String {
        var t = text
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        t = t.replacingOccurrences(of: " ,", with: ",")
        while t.contains(",,") { t = t.replacingOccurrences(of: ",,", with: ",") }
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - TimeNormalizer

/// Converts common Whisper time mishaps into clean clock forms.
/// On the hour + am/pm → "3pm" (not "3:00" / "3,00").
enum TimeNormalizer {
    
    static func normalize(_ raw: String) -> String {
        var t = raw
        t = spokenPhrases(t)
        t = digitTimes(t)
        t = amPmCleanup(t)
        return t
    }
    
    // MARK: Digit clocks
    
    private static func digitTimes(_ text: String) -> String {
        var t = text
        
        // Broken style: "3,00" / "3,00pm" / "3,30"
        t = replace(t, #"(?i)\b(\d{1,2}),(\d{2})\s*(a\.?m\.?|p\.?m\.?)?\b"#) { m in
            guard let h = Int(m[1]), let min = Int(m[2]), isValidClock(h: h, m: min) else { return m[0] }
            return formatTime(h: h, m: min, mer: m[3])
        }
        
        // "3:30pm" / "3:00" / "3:00pm"
        t = replace(t, #"(?i)\b(\d{1,2}):(\d{2})\s*(a\.?m\.?|p\.?m\.?)?\b"#) { m in
            guard let h = Int(m[1]), let min = Int(m[2]), isValidClock(h: h, m: min) else { return m[0] }
            return formatTime(h: h, m: min, mer: m[3])
        }
        
        // "3:30 p m"
        t = replace(t, #"(?i)\b(\d{1,2}):(\d{2})\s*([ap])\s*\.?\s*m\.?\b"#) { m in
            guard let h = Int(m[1]), let min = Int(m[2]), isValidClock(h: h, m: min) else { return m[0] }
            return formatTime(h: h, m: min, mer: m[3] + "m")
        }
        
        // "3, 30pm" / "3.30 pm"
        t = replace(t, #"(?i)\b(\d{1,2})\s*[,.]\s*(\d{2})\s*(a\.?m\.?|p\.?m\.?)?\b"#) { m in
            guard let h = Int(m[1]), let min = Int(m[2]), isValidClock(h: h, m: min) else { return m[0] }
            return formatTime(h: h, m: min, mer: m[3])
        }
        
        // "3 30 pm"
        t = replace(t, #"(?i)\b(\d{1,2})\s+(\d{2})\s*(a\.?m\.?|p\.?m\.?)\b"#) { m in
            guard let h = Int(m[1]), let min = Int(m[2]), isValidClock(h: h, m: min) else { return m[0] }
            return formatTime(h: h, m: min, mer: m[3])
        }
        
        // "at 3 30"
        t = replace(
            t,
            #"(?i)\b(at|around|about|by|from|until|till|before|after|for)\s+(\d{1,2})\s+(\d{2})\b"#
        ) { m in
            guard let h = Int(m[2]), let min = Int(m[3]), isValidClock(h: h, m: min) else { return m[0] }
            return "\(m[1]) \(formatTime(h: h, m: min, mer: ""))"
        }
        
        // Trailing "3 30"
        t = replace(t, #"(?i)\b(\d{1,2})\s+(\d{2})\s*$"#) { m in
            guard let h = Int(m[1]), let min = Int(m[2]), isValidClock(h: h, m: min) else { return m[0] }
            return formatTime(h: h, m: min, mer: "")
        }
        
        // "330pm"
        t = replace(t, #"(?i)\b(\d{1,2})(\d{2})\s*(a\.?m\.?|p\.?m\.?)\b"#) { m in
            guard let h = Int(m[1]), let min = Int(m[2]), isValidClock(h: h, m: min) else { return m[0] }
            return formatTime(h: h, m: min, mer: m[3])
        }
        
        // "3 pm" → "3pm"
        t = replace(t, #"(?i)\b(\d{1,2})\s*(a\.?m\.?|p\.?m\.?)\b"#) { m in
            guard let h = Int(m[1]), h >= 0, h <= 23 else { return m[0] }
            let mer = normalizeMeridiem(m[2])
            guard !mer.isEmpty else { return m[0] }
            return "\(h)\(mer)"
        }
        
        return t
    }
    
    // MARK: Spoken phrases
    
    private static func spokenPhrases(_ text: String) -> String {
        var t = text
        
        t = replace(t, #"(?i)\bhalf\s+past\s+(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#) { m in
            guard let h = parseHour(m[1]) else { return m[0] }
            return formatTime(h: h, m: 30, mer: "")
        }
        
        t = replace(t, #"(?i)\bquarter\s+past\s+(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#) { m in
            guard let h = parseHour(m[1]) else { return m[0] }
            return formatTime(h: h, m: 15, mer: "")
        }
        
        t = replace(t, #"(?i)\bquarter\s+to\s+(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#) { m in
            guard let h = parseHour(m[1]) else { return m[0] }
            let hour = h == 1 ? 12 : h - 1
            return formatTime(h: hour, m: 45, mer: "")
        }
        
        t = replace(t, #"(?i)\b(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s*o['’]?\s*clock\s*(a\.?m\.?|p\.?m\.?)?\b"#) { m in
            guard let h = parseHour(m[1]) else { return m[0] }
            return formatTime(h: h, m: 0, mer: m[2])
        }
        
        t = replace(
            t,
            #"(?i)\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(oh\s+)?(zero|oh|five|ten|fifteen|twenty|twenty[\s-]?five|thirty|thirty[\s-]?five|forty|forty[\s-]?five|fifty|fifty[\s-]?five)\s*(a\.?m\.?|p\.?m\.?)?\b"#
        ) { m in
            guard let h = parseHour(m[1]), let min = parseMinute(m[3]) else { return m[0] }
            return formatTime(h: h, m: min, mer: m[4])
        }
        
        t = replace(
            t,
            #"(?i)\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s*(a\.?m\.?|p\.?m\.?)\b"#
        ) { m in
            guard let h = parseHour(m[1]) else { return m[0] }
            return "\(h)\(normalizeMeridiem(m[2]))"
        }
        
        t = replace(t, #"(?i)\bat\s+noon\b"#, "at 12pm")
        t = replace(t, #"(?i)\bat\s+midnight\b"#, "at 12am")
        
        return t
    }
    
    private static func amPmCleanup(_ text: String) -> String {
        var t = text
        t = replace(t, #"(?i)\b(\d{1,2}:\d{2})\s*a\.?\s*m\.?\b"#, "$1am")
        t = replace(t, #"(?i)\b(\d{1,2}:\d{2})\s*p\.?\s*m\.?\b"#, "$1pm")
        t = replace(t, #"(?i)\b(\d{1,2})\s*a\.?\s*m\.?\b"#, "$1am")
        t = replace(t, #"(?i)\b(\d{1,2})\s*p\.?\s*m\.?\b"#, "$1pm")
        t = replace(t, #"(?i)\b(\d{1,2}:\d{2})(am|pm)(?:am|pm)+\b"#, "$1$2")
        return t
    }
    
    // MARK: - Format helpers
    
    private static func isValidClock(h: Int, m: Int) -> Bool {
        (h >= 0 && h <= 23) && (m >= 0 && m <= 59)
    }
    
    /// On the hour + am/pm → "3pm". With minutes → "3:30pm".
    private static func formatTime(h: Int, m: Int, mer: String) -> String {
        let merNorm = normalizeMeridiem(mer)
        if m == 0 {
            if !merNorm.isEmpty { return "\(h)\(merNorm)" }
            return "\(h):00"
        }
        return String(format: "%d:%02d%@", h, m, merNorm)
    }
    
    private static func normalizeMeridiem(_ raw: String) -> String {
        let s = raw.lowercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
        if s.hasPrefix("a") { return "am" }
        if s.hasPrefix("p") { return "pm" }
        return ""
    }
    
    private static func parseHour(_ raw: String) -> Int? {
        if let n = Int(raw), (0...23).contains(n) { return n }
        let map: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
            "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12
        ]
        return map[raw.lowercased()]
    }
    
    private static func parseMinute(_ raw: String) -> Int? {
        var s = raw.lowercased().replacingOccurrences(of: "-", with: " ")
        s = s.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        let map: [String: Int] = [
            "zero": 0, "oh": 0, "o": 0,
            "five": 5, "ten": 10, "fifteen": 15,
            "twenty": 20, "twenty five": 25, "twentyfive": 25,
            "thirty": 30, "thirty five": 35, "thirtyfive": 35,
            "forty": 40, "forty five": 45, "fortyfive": 45,
            "fifty": 50, "fifty five": 55, "fiftyfive": 55
        ]
        if let n = map[s] { return n }
        if let n = Int(s), (0...59).contains(n) { return n }
        return nil
    }
    
    // MARK: - Regex
    
    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
    
    private static func replace(
        _ text: String,
        _ pattern: String,
        transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsOrig = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsOrig.length))
        guard !matches.isEmpty else { return text }
        
        var result = text
        for match in matches.reversed() {
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                let r = match.range(at: i)
                groups.append(r.location == NSNotFound ? "" : nsOrig.substring(with: r))
            }
            let replacement = transform(groups)
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }
}
