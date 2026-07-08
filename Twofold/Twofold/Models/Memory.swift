//
//  Memory.swift
//  Twofold
//

import Foundation

struct Memory: Identifiable, Hashable {
    let id: UUID
    var title: String
    var emoji: String
    var place: Place
    var date: Date
    var note: String
    /// Placeholder gradient seed until real photo assets exist.
    var photoSeed: Int

    init(
        id: UUID = UUID(),
        title: String,
        emoji: String,
        place: Place,
        date: Date,
        note: String,
        photoSeed: Int
    ) {
        self.id = id
        self.title = title
        self.emoji = emoji
        self.place = place
        self.date = date
        self.note = note
        self.photoSeed = photoSeed
    }
}
