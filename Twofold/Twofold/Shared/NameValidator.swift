//
//  NameValidator.swift
//  Twofold
//
//  Structural checks (length, character set) plus a hardcoded inappropriate-name blocklist.
//  Everything runs locally and synchronously — the old server-side LLM moderation call
//  (NameModerationService) made the Continue button noticeably slow.
//

import Foundation

enum NameValidator {
    static let minLength = 2
    /// Letters plus the punctuation real names actually use (space, hyphen, apostrophe) —
    /// no digits or other symbols.
    private static let allowedCharacters = CharacterSet.letters.union(CharacterSet(charactersIn: " '-"))

    /// Slurs/profanity blocked wherever they appear in the name, even embedded in a longer
    /// word (e.g. "F***face"). Only terms that never occur inside real names belong here —
    /// shorter or ambiguous terms go in `bannedWords` instead to avoid Scunthorpe-style
    /// false positives (e.g. "Kikelomo" contains "kike", "Analise" contains "anal").
    private static let bannedSubstrings: [String] = [
        "fuck", "shit", "bitch", "cunt", "whore", "slut", "wank", "twat",
        "nigg", "faggot", "retard", "dildo", "penis", "vagina", "hitler",
    ]

    /// Terms only blocked as a standalone word (between spaces/hyphens/apostrophes),
    /// because they can legitimately appear inside real names ("Cassandra", "Cockburn").
    private static let bannedWords: Set<String> = [
        "ass", "arse", "dick", "cock", "tits", "hoe", "fag", "prick",
        "nazi", "kike", "spic", "chink", "coon", "cum", "sex", "porn",
    ]

    /// Returns a user-facing error to show, or `nil` if the name passes structural checks.
    static func structuralError(for rawName: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard name.count >= minLength else {
            return "Enter at least \(minLength) characters."
        }
        guard name.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            return "Names can only contain letters."
        }
        return nil
    }

    /// Returns `true` if the name hits the inappropriate-name blocklist.
    static func isInappropriate(_ rawName: String) -> Bool {
        // Fold case and diacritics so e.g. "FÜCK" still matches "fuck".
        let folded = rawName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()

        let words = folded.split(whereSeparator: { " '-".contains($0) }).map(String.init)
        if words.contains(where: bannedWords.contains) { return true }

        // Squash separators so "f u c k" / "f-u-c-k" can't dodge the substring check.
        let squashed = folded.filter { !" '-".contains($0) }
        return bannedSubstrings.contains { squashed.contains($0) }
    }
}
