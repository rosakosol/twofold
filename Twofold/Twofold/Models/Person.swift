//
//  Person.swift
//  Twofold
//

import SwiftUI

struct Person: Identifiable, Hashable {
    let id: UUID
    var name: String
    /// Unset until the person completes the "where are you based?" onboarding step
    /// (or a partner who hasn't onboarded on their own device yet, in this backend-less demo).
    var homeCity: Place?
    var accentColor: Color

    init(id: UUID = UUID(), name: String, homeCity: Place? = nil, accentColor: Color) {
        self.id = id
        self.name = name
        self.homeCity = homeCity
        self.accentColor = accentColor
    }

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.compactMap { $0.first }.prefix(2)
        return String(letters).uppercased()
    }
}
