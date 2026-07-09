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
    /// Gradient seed used for the placeholder shown while there's no photo (or one hasn't
    /// loaded yet) — derived from `id` for real memories so it's stable across loads.
    var photoSeed: Int
    /// Signed URL for the uploaded photo, if any. `memory-photos` is a private bucket, so
    /// this is time-limited rather than a stable public URL — re-resolved on every fetch.
    var photoURL: URL?

    init(
        id: UUID = UUID(),
        title: String,
        emoji: String,
        place: Place,
        date: Date,
        note: String,
        photoSeed: Int? = nil,
        photoURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.emoji = emoji
        self.place = place
        self.date = date
        self.note = note
        self.photoSeed = photoSeed ?? abs(id.hashValue % 4)
        self.photoURL = photoURL
    }
}
