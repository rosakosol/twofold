//
//  Memory.swift
//  Twofold
//

import Foundation

/// One uploaded photo attached to a memory. Identified by its `memory_photos` row id so an
/// individual photo can be removed later without touching the rest of the set.
struct MemoryPhoto: Identifiable, Hashable, Codable {
    let id: UUID
    var path: String
    /// Signed URL, re-resolved on every fetch since `memory-photos` is a private bucket. Also
    /// used to point at a local `file://` URL for a memory that hasn't synced to the backend
    /// yet — see `PendingMemoryStore` — so every photo-rendering view works unchanged either way.
    var url: URL
}

struct Memory: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    /// Optional — a memory doesn't need a place to be worth saving.
    var place: Place?
    var date: Date
    var note: String
    /// Gradient seed used for the placeholder shown while there's no photo (or one hasn't
    /// loaded yet) — derived from `id` for real memories so it's stable across loads.
    var photoSeed: Int
    /// Photos in display order, if any.
    var photos: [MemoryPhoto]
    /// Set when a memory is explicitly linked to a trip from Trip Details — nil by default;
    /// unlike `place`/`date` this is never inferred automatically.
    var tripID: UUID?

    var photoURLs: [URL] { photos.map(\.url) }
    var photoURL: URL? { photos.first?.url }

    init(
        id: UUID = UUID(),
        title: String,
        place: Place?,
        date: Date,
        note: String,
        photoSeed: Int? = nil,
        photos: [MemoryPhoto] = [],
        tripID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.place = place
        self.date = date
        self.note = note
        self.photoSeed = photoSeed ?? abs(id.hashValue % 4)
        self.photos = photos
        self.tripID = tripID
    }
}
