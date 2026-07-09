//
//  NameValidator.swift
//  Twofold
//
//  Structural checks only (length, character set) — offensive-content detection is a
//  separate server-side call (see NameModerationService) rather than a hardcoded wordlist.
//

import Foundation

enum NameValidator {
    static let minLength = 2

    /// Letters plus the punctuation real names actually use (space, hyphen, apostrophe) —
    /// no digits or other symbols.
    private static let allowedCharacters = CharacterSet.letters.union(CharacterSet(charactersIn: " '-"))

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
}
