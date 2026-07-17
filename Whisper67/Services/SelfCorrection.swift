import Foundation

/// Applies mid-utterance spoken corrections so the final intent wins.
/// Example: "Thursday, no actually Friday at 3, 30pm" → "Friday at 3:30pm"
enum SelfCorrection {
    
    static func apply(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        
        // Normalize spoken times first (helps "3, 30pm" / "3 30 pm")
        t = normalizeTimes(t)
        
        // Apply correction patterns until stable (handles chained fixes)
        for _ in 0..<4 {
            let next = applyOnce(t)
            if next == t { break }
            t = next
        }
        
        t = cleanupArtifacts(t)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - One pass
    
    private static func applyOnce(_ text: String) -> String {
        var t = text
        
        // "Thursday, no, actually Friday" / "Thursday wait no Friday" / "Thursday no Friday"
        // Keep the replacement token only.
        t = replace(
            in: t,
            pattern: #"(?i)\b([\w']+)(?:\s*[,;])?\s+(?:wait\s+)?(?:no|nope|nah)(?:\s*[,;])?\s+(?:actually\s+|i\s+mean\s+)?([\w']+)\b"#,
            template: "$2"
        )
        
        // Multi-word slot: "next week, no actually next month"
        t = replace(
            in: t,
            pattern: #"(?i)\b([\w']+(?:\s+[\w']+){0,3})(?:\s*[,;])?\s+(?:wait\s+)?(?:no|nope)(?:\s*[,;])?\s+(?:actually\s+|i\s+mean\s+)([\w']+(?:\s+[\w']+){0,3})\b"#,
            template: "$2"
        )
        
        // "wait no Friday" with no clear prior (drop the wait-no)
        t = replace(
            in: t,
            pattern: #"(?i)\bwait\s*,?\s*no(?:\s*,)?\s+(?:actually\s+)?"#,
            template: ""
        )
        
        // Standalone "no, actually" / "no actually" between clauses
        t = replace(
            in: t,
            pattern: #"(?i)(?:\s*[,;])?\s*\bno(?:\s*,)?\s+actually\b\s*"#,
            template: " "
        )
        
        // "I mean Friday" after something — keep "I mean X" → X when short
        t = replace(
            in: t,
            pattern: #"(?i)\b([\w']+)(?:\s*[,;])?\s+i\s+mean\s+([\w']+)\b"#,
            template: "$2"
        )
        
        // "scratch that" / "forget that" — drop the marker phrase only
        t = replace(
            in: t,
            pattern: #"(?i)\b(?:scratch that|forget that|ignore that|correction)\b[,:]?\s*"#,
            template: ""
        )
        
        // Day-specific (extra safety if generic pattern missed punctuation)
        let days = "monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|tomorrow|tonight"
        t = replace(
            in: t,
            pattern: "(?i)\\b(\(days))\\b(?:\\s*[,;])?\\s+(?:wait\\s+)?(?:no|nope)(?:\\s*[,;])?\\s+(?:actually\\s+)?\\b(\(days))\\b",
            template: "$2"
        )
        
        return t
    }
    
    // MARK: - Times
    
    /// "3, 30pm" / "3.30 pm" / "3 30 p.m." → "3:30pm"
    private static func normalizeTimes(_ text: String) -> String {
        var t = text
        // 3, 30pm  |  3,30 pm  |  3.30pm  |  3 30 pm
        t = replace(
            in: t,
            pattern: #"(?i)\b(\d{1,2})\s*[,.]\s*(\d{2})\s*(a\.?m\.?|p\.?m\.?)?\b"#,
            template: "$1:$2$3"
        )
        t = replace(
            in: t,
            pattern: #"(?i)\b(\d{1,2})\s+(\d{2})\s*(a\.?m\.?|p\.?m\.?)\b"#,
            template: "$1:$2$3"
        )
        // Normalize "p.m." → "pm"
        t = replace(in: t, pattern: #"(?i)\b(\d{1,2}:\d{2})\s*a\.?m\.?\b"#, template: "$1am")
        t = replace(in: t, pattern: #"(?i)\b(\d{1,2}:\d{2})\s*p\.?m\.?\b"#, template: "$1pm")
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
        // Double spaces / lonely commas
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        t = t.replacingOccurrences(of: " ,", with: ",")
        while t.contains(",,") { t = t.replacingOccurrences(of: ",,", with: ",") }
        t = t.replacingOccurrences(of: " ,", with: ",")
        // "for  Friday" style
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
