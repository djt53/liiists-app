import Foundation

/// Client-side objectionable-content filter applied at the publish and
/// feed-render boundaries to satisfy Apple guideline 1.2 for anonymous UGC.
/// Decision 014.
///
/// The wordlist is intentionally small and conservative — it catches the
/// most common slurs and obvious profanity. False negatives are caught by
/// the Report flow (T-51i) and the 24-hour moderation SLA backed by the
/// EjectedAuthor mechanism (T-215). False positives are addressable by
/// editing this file and shipping an update.
///
/// Matching is case-insensitive with word boundaries so "scunthorpe" does
/// not match "cunt". Non-ASCII whitespace and common obfuscation (zero-width
/// joiners, asterisks between letters) are not currently handled — the
/// expectation is that report + ejection picks up the rest.
enum ContentFilter {

    /// Returns true when the input contains no flagged terms.
    static func isClean(_ text: String) -> Bool {
        firstMatch(text) == nil
    }

    /// Returns the first flagged term found, or nil if the input is clean.
    /// Surfaced in the publish-error copy so the user understands what's
    /// being rejected.
    static func firstMatch(_ text: String) -> String? {
        let lowered = text.lowercased()
        for term in flagged {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: term))\\b"
            if lowered.range(of: pattern, options: .regularExpression) != nil {
                return term
            }
        }
        return nil
    }

    /// Convenience for the publish boundary — checks title and every item
    /// in one call. Returns the first flagged term seen anywhere in the list.
    static func firstMatchInList(title: String, items: [String]) -> String? {
        if let m = firstMatch(title) { return m }
        for item in items {
            if let m = firstMatch(item) { return m }
        }
        return nil
    }

    /// Slurs + obvious profanity. Maintained inline so updates ship with the
    /// app binary — no network dependency. Order doesn't matter; matching is
    /// O(n) on the list and the list stays small.
    private static let flagged: [String] = [
        // Slurs (racial, ethnic, anti-LGBTQ). Intentionally explicit so the
        // filter does its job; this list is the entire reason the filter exists.
        "nigger", "nigga", "chink", "spic", "kike", "gook", "wetback",
        "raghead", "towelhead", "tranny", "faggot", "fag", "dyke", "retard",
        // Sexual content
        "porn", "porno", "xxx", "nsfw",
        // Profanity — covers the common stems. App Store accepts profanity
        // in user content if there's a filter; this is the filter.
        "fuck", "shit", "cunt", "bitch", "bastard", "asshole", "dickhead",
        // Targeted-violence / harassment terms
        "kys", "kill yourself", "killyourself"
    ]
}
