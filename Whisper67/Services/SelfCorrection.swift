import Foundation

/// Applies mid-utterance spoken corrections so the final intent wins,
/// and normalizes spoken clock times into readable forms.
///
/// Example: "Thursday, no actually Friday at 3, 30pm" → "Friday at 3:30pm"
enum SelfCorrection {
    
    static func apply(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        
        // Times before corrections so "3, 30" is not mangled by comma rules
        t = TimeNormalizer.normalize(t)
        
        for _ in 0..<4 {
            let next = applyOnce(t)
            if next == t { break }
            t = next
        }
        
        // Times again in case a correction left "3 30 pm"
        t = TimeNormalizer.normalize(t)
        t = cleanupArtifacts(t)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Self-correction pass
    
    private static func applyOnce(_ text: String) -> String {
        var t = text
        
        t = replace(
            in: t,
            pattern: #"(?i)\b([\w']+)(?:\s*[,;])?\s+(?:wait\s+)?(?:no|nope|nah)(?:\s*[,;])?\s+(?:actually\s+|i\s+mean\s+)?([\w']+)\b"#,
            template: "$2"
        )
        
        t = replace(
            in: t,
            pattern: #"(?i)\b([\w']+(?:\s+[\w']+){0,3})(?:\s*[,;])?\s+(?:wait\s+)?(?:no|nope)(?:\s*[,;])?\s+(?:actually\s+|i\s+mean\s+)([\w']+(?:\s+[\w']+){0,3})\b"#,
            template: "$2"
        )
        
        t = replace(
            in: t,
            pattern: #"(?i)\bwait\s*,?\s*no(?:\s*,)?\s+(?:actually\s+)?"#,
            template: ""
        )
        
        t = replace(
            in: t,
            pattern: #"(?i)(?:\s*[,;])?\s*\bno(?:\s*,)?\s+actually\b\s*"#,
            template: " "
        )
        
        t = replace(
            in: t,
            pattern: #"(?i)\b([\w']+)(?:\s*[,;])?\s+i\s+mean\s+([\w']+)\b"#,
            template: "$2"
        )
        
        t = replace(
            in: t,
            pattern: #"(?i)\b(?:scratch that|forget that|ignore that|correction)\b[,:]?\s*"#,
            template: ""
        )
        
        let days = "monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|tomorrow|tonight"
        t = replace(
            in: t,
            pattern: "(?i)\\b(\(days))\\b(?:\\s*[,;])?\\s+(?:wait\\s+)?(?:no|nope)(?:\\s*[,;])?\\s+(?:actually\\s+)?\\b(\(days))\\b",
            template: "$2"
        )
        
        return t
    }
    
    // MARK: - Helpers
    
    private static func replace(in text: String, pattern: String, template: String) -> String {
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

/// Converts common Whisper time mishaps into H:MM[am|pm].
enum TimeNormalizer {
    
    static func normalize(_ raw: String) -> String {
        var t = raw
        
        // Spoken phrases first (half past / quarter / o'clock / three thirty)
        t = spokenPhrases(t)
        
        // Digit forms
        t = digitTimes(t)
        
        // Final am/pm cleanup (p.m. → pm, attach to time)
        t = amPmCleanup(t)
        
        return t
    }
    
    // MARK: Digit clocks
    
    private static func digitTimes(_ text: String) -> String {
        var t = text
        
        // Already "3:30" with spaced am/pm → "3:30pm"
        t = replace(t, #"(?i)\b(\d{1,2}):(\d{2})\s*(a\.?m\.?|p\.?m\.?)\b"#, "$1:$2$3")
        
        // 3:30pm already fine; fix 3:30 p m
        t = replace(t, #"(?i)\b(\d{1,2}):(\d{2})\s*([ap])\s*\.?\s*m\.?\b"#, "$1:$2$3m")
        
        // 3,30 / 3.30 / 3, 30 ± am/pm
        t = replace(t, #"(?i)\b(\d{1,2})\s*[,.]\s*(\d{2})\s*(a\.?m\.?|p\.?m\.?)?\b"#) { m in
            guard let h = Int(m[1]), let min = Int(m[2]), isValidClock(h: h, m: min) else { return m[0] }
            return formatTime(h: h, m: min, mer: m[3])
        }
        
        // 3 30 pm / 3 30 a.m.
        t = replace(t, #"(?i)\b(\d{1,2})\s+(\d{2})\s*(a\.?m\.?|p\.?m\.?)\b"#) { m in
            guard let h = Int(m[1]), let min = Int(m[2]), isValidClock(h: h, m: min) else { return m[0] }
            return formatTime(h: h, m: min, mer: m[3])
        }
        
        // "at 3 30" / "by 12 00" / "around 10 15" without am/pm
        // (capture the preposition — lookbehind can't be variable-width in NSRegularExpression)
        t = replace(
            t,
            #"(?i)\b(at|around|about|by|from|until|till|before|after|for)\s+(\d{1,2})\s+(\d{2})\b"#
        ) { m in
            guard let h = Int(m[2]), let min = Int(m[3]), isValidClock(h: h, m: min) else { return m[0] }
            return "\(m[1]) \(formatTime(h: h, m: min, mer: ""))"
        }
        
        // Trailing "3 30" at end of phrase (common Whisper output)
        t = replace(t, #"(?i)\b(\d{1,2})\s+(\d{2})\s*$"#) { m in
            guard let h = Int(m[1]), let min = Int(m[2]), isValidClock(h: h, m: min) else { return m[0] }
            return formatTime(h: h, m: min, mer: "")
        }
        
        // "330pm" / "330 pm" compact
        t = replace(t, #"(?i)\b(\d{1,2})(\d{2})\s*(a\.?m\.?|p\.?m\.?)\b"#) { m in
            guard let h = Int(m[1]), let min = Int(m[2]), isValidClock(h: h, m: min) else { return m[0] }
            return formatTime(h: h, m: min, mer: m[3])
        }
        
        return t
    }
    
    // MARK: Spoken phrases
    
    private static func spokenPhrases(_ text: String) -> String {
        var t = text
        
        // half past 3 / half past three → 3:30
        t = replace(t, #"(?i)\bhalf\s+past\s+(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#) { m in
            guard let h = parseHour(m[1]) else { return m[0] }
            return formatTime(h: h, m: 30, mer: "")
        }
        
        // quarter past 4 → 4:15
        t = replace(t, #"(?i)\bquarter\s+past\s+(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#) { m in
            guard let h = parseHour(m[1]) else { return m[0] }
            return formatTime(h: h, m: 15, mer: "")
        }
        
        // quarter to 5 → 4:45
        t = replace(t, #"(?i)\bquarter\s+to\s+(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#) { m in
            guard let h = parseHour(m[1]) else { return m[0] }
            let hour = h == 1 ? 12 : h - 1
            return formatTime(h: hour, m: 45, mer: "")
        }
        
        // 3 o'clock / 3 oclock → 3:00
        t = replace(t, #"(?i)\b(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s*o['’]?\s*clock\b"#) { m in
            guard let h = parseHour(m[1]) else { return m[0] }
            return formatTime(h: h, m: 0, mer: "")
        }
        
        // Explicit: hour-word + minute-word [am/pm]
        t = replace(
            t,
            #"(?i)\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(oh\s+)?(zero|oh|five|ten|fifteen|twenty|twenty[\s-]?five|thirty|thirty[\s-]?five|forty|forty[\s-]?five|fifty|fifty[\s-]?five)\s*(a\.?m\.?|p\.?m\.?)?\b"#
        ) { m in
            guard let h = parseHour(m[1]), let min = parseMinute(m[3]) else { return m[0] }
            return formatTime(h: h, m: min, mer: m[4])
        }
        
        // three pm → 3pm (hour only with meridian)
        t = replace(
            t,
            #"(?i)\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s*(a\.?m\.?|p\.?m\.?)\b"#
        ) { m in
            guard let h = parseHour(m[1]) else { return m[0] }
            let mer = normalizeMeridiem(m[2])
            return "\(h)\(mer)"
        }
        
        // noon / midnight
        t = replace(t, #"(?i)\bat\s+noon\b"#, "at 12:00pm")
        t = replace(t, #"(?i)\bat\s+midnight\b"#, "at 12:00am")
        
        return t
    }
    
    private static func amPmCleanup(_ text: String) -> String {
        var t = text
        // "3:30 p.m." → "3:30pm"
        t = replace(t, #"(?i)\b(\d{1,2}:\d{2})\s*a\.?\s*m\.?\b"#, "$1am")
        t = replace(t, #"(?i)\b(\d{1,2}:\d{2})\s*p\.?\s*m\.?\b"#, "$1pm")
        t = replace(t, #"(?i)\b(\d{1,2})\s*a\.?\s*m\.?\b"#, "$1am")
        t = replace(t, #"(?i)\b(\d{1,2})\s*p\.?\s*m\.?\b"#, "$1pm")
        // Fix double meridian "3:30pmpm"
        t = replace(t, #"(?i)\b(\d{1,2}:\d{2})(am|pm)(?:am|pm)+\b"#, "$1$2")
        return t
    }
    
    // MARK: - Format helpers
    
    private static func isValidClock(h: Int, m: Int) -> Bool {
        // 12h or 24h hour, minutes 0–59
        (h >= 0 && h <= 23) && (m >= 0 && m <= 59)
    }
    
    private static func formatTime(h: Int, m: Int, mer: String) -> String {
        let merNorm = normalizeMeridiem(mer)
        if m == 0 && merNorm.isEmpty {
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
        if let n = Int(raw) { return (1...23).contains(n) ? n : nil }
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
        // "oh five" already handled; try Int
        if let n = Int(s), (0...59).contains(n) { return n }
        return nil
    }
    
    // MARK: - Regex helpers
    
    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
    
    /// Match with capture groups available as m[0]=full, m[1]=group1, …
    private static func replace(
        _ text: String,
        _ pattern: String,
        transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        
        var result = text
        // Reverse so ranges stay valid
        for match in matches.reversed() {
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                let r = match.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            let replacement = transform(groups)
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}
