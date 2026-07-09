//
//  Person.swift
//  Twofold
//

import SwiftUI

struct Person: Identifiable, Hashable {
    let id: UUID
    var name: String
    /// Unset until the person completes the "where are you based?" onboarding step,
    /// or for a partner who hasn't set theirs yet.
    var homeCity: Place?
    var accentColor: Color
    /// Public URL for their uploaded profile photo. Nil falls back to the initials avatar.
    var avatarURL: URL?

    init(id: UUID = UUID(), name: String, homeCity: Place? = nil, accentColor: Color, avatarURL: URL? = nil) {
        self.id = id
        self.name = name
        self.homeCity = homeCity
        self.accentColor = accentColor
        self.avatarURL = avatarURL
    }

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.compactMap { $0.first }.prefix(2)
        return String(letters).uppercased()
    }
}
