//
//  BackendService+Memories.swift
//  Twofold
//
//  Memories and their photos.
//

import Foundation
import Supabase

extension BackendService {

    #if DEBUG
    /// See the test seams in `BackendService+Trips.swift`.
    static func memoryUpdateForTesting(placeID: Changed<UUID?>?, title: String?, note: String?, occurredAt: Date? = nil) -> some Encodable {
        MemoryUpdate(placeId: placeID, title: title, note: note, occurredAt: occurredAt)
    }
    #endif

    /// Pass `nil` to unlink — the only write path for `memories.trip_id`, since a memory has
    /// no other route to a trip (no automatic place/date matching).
    static func setMemoryTrip(memoryID: UUID, tripID: UUID?) async throws {
        try await supabase
            .from("memories")
            .update(TripIDUpdate(tripId: tripID))
            .eq("id", value: memoryID)
            .execute()
    }

    // MARK: - Memories

    struct MemoryRow: Decodable {
        var id: UUID
        var placeId: UUID?
        var title: String
        var note: String
        var occurredAt: Date
        var tripId: UUID?

        enum CodingKeys: String, CodingKey {
            case id, title, note
            case placeId = "place_id"
            case occurredAt = "occurred_at"
            case tripId = "trip_id"
        }
    }

    private struct MemoryInsert: Encodable {
        var id: UUID
        var coupleId: UUID
        var placeId: UUID?
        var title: String
        var note: String
        var occurredAt: Date

        enum CodingKeys: String, CodingKey {
            case id, title, note
            case coupleId = "couple_id"
            case placeId = "place_id"
            case occurredAt = "occurred_at"
        }
    }

    /// Only the columns a `MemoryEdit` changed, the rest left out so PostgREST leaves them alone.
    /// `placeId` is explicit for the same reason as `TripIDUpdate` — a memory losing its place
    /// has to write a null, not omit the column and keep the old one.
    private struct MemoryUpdate: Encodable {
        var placeId: Changed<UUID?>?
        var title: String?
        var note: String?
        var occurredAt: Date?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let placeId { try container.encode(placeId.value, forKey: .placeId) }
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(note, forKey: .note)
            try container.encodeIfPresent(occurredAt, forKey: .occurredAt)
        }

        enum CodingKeys: String, CodingKey {
            case title, note
            case placeId = "place_id"
            case occurredAt = "occurred_at"
        }
    }

    struct MemoryPhotoRow: Decodable {
        var id: UUID
        var memoryId: UUID
        var photoPath: String
        var position: Int

        enum CodingKeys: String, CodingKey {
            case id, position
            case memoryId = "memory_id"
            case photoPath = "photo_path"
        }
    }

    private struct MemoryPhotoInsert: Encodable {
        var memoryId: UUID
        var photoPath: String
        var position: Int

        enum CodingKeys: String, CodingKey {
            case position
            case memoryId = "memory_id"
            case photoPath = "photo_path"
        }
    }

    /// `memory-photos` is a private bucket (unlike `avatars`) — these are personal photos —
    /// so display goes through a time-limited signed URL rather than a stable public one.
    static func memoryPhotoSignedURL(path: String) async throws -> URL {
        try await R2Storage.readURL(.memoryPhoto, path: path)
    }

    /// A single transient failure here (network blip, momentary auth hiccup) used to mean a
    /// callers' `try?` silently dropped the photo forever — the underlying file and DB row
    /// were both fine, but the photo just never showed up, looking exactly like "the image
    /// wasn't saved" even though it was. Retries a few times before actually giving up.
    /// Signs a whole set of photo paths in one request, keyed by path.
    ///
    /// `createSignedURLs` is a single POST to `object/sign/{bucket}`, where the previous approach
    /// was one `createSignedURL` per photo. Those were already concurrent, but concurrent N is
    /// still N: a couple with 200 memories averaging three photos opened 600 connections, which
    /// queue against the client's connection limit and arrive at the server together — and
    /// `fetchCoupleState` cannot publish anything until the slowest of them returns.
    ///
    /// Keyed by path rather than by photo id because that is what the API returns, and because
    /// two rows pointing at the same file should not be signed twice.
    ///
    /// Anything the batch could not sign falls back to the per-path retry, which is exactly what
    /// every photo used to do. So a partial failure — or a batch that fails outright — costs the
    /// affected photos a slower path rather than costing them their URL. That matters: a photo
    /// with no URL is dropped from the model entirely by the callers below.
    static func memoryPhotoSignedURLs(paths: [String]) async -> [String: URL] {
        let unique = Array(Set(paths))
        guard !unique.isEmpty else { return [:] }

        // Already keyed by the path that was asked for, so the suffix/leading-slash matching the
        // Storage API needed is gone: `storage-url` echoes back exactly the keys it was given.
        var signed = await R2Storage.readURLs(.memoryPhoto, paths: unique)

        let missing = unique.filter { signed[$0] == nil }
        guard !missing.isEmpty else { return signed }

        await withTaskGroup(of: (String, URL?).self) { group in
            for path in missing {
                group.addTask { (path, await memoryPhotoSignedURLWithRetry(path: path)) }
            }
            for await (path, url) in group {
                if let url { signed[path] = url }
            }
        }
        return signed
    }

    static func memoryPhotoSignedURLWithRetry(path: String, attempts: Int = 3) async -> URL? {
        for attempt in 1...attempts {
            if let url = try? await memoryPhotoSignedURL(path: path) {
                return url
            }
            if attempt < attempts {
                try? await Task.sleep(for: .milliseconds(400 * attempt))
            }
        }
        return nil
    }

    /// Couple-scoped re-fetch (mirrors `fetchFlights(coupleID:)`) — unlike flights, memories
    /// were previously only ever loaded once via `fetchCoupleState()`'s bulk adopt, so a
    /// partner's newly-added memory never appeared until the next full couple-state reload
    /// (typically only on relaunch). This lets `AppModel.refreshMemories()` pull just the
    /// memories table on foreground, same cadence as flights.
    static func fetchMemories(coupleID: UUID) async throws -> [Memory] {
        let memoryRows: [MemoryRow] = try await supabase
            .from("memories")
            .select()
            .eq("couple_id", value: coupleID)
            .execute()
            .value

        let memoryPhotoRows: [MemoryPhotoRow]
        if memoryRows.isEmpty {
            memoryPhotoRows = []
        } else {
            memoryPhotoRows = try await supabase
                .from("memory_photos")
                .select()
                .in("memory_id", values: memoryRows.map(\.id))
                .order("position")
                .execute()
                .value
        }

        let placeIDs = Array(Set(memoryRows.compactMap(\.placeId)))
        let places = try await fetchPlaces(ids: placeIDs)

        // One request for the whole set — see `memoryPhotoSignedURLs`. This path runs on every
        // foreground refresh, so it was re-signing every photo the couple has ever added each
        // time the app came back.
        let signedURLsByPath = await memoryPhotoSignedURLs(paths: memoryPhotoRows.map(\.photoPath))
        return makeMemories(rows: memoryRows, photoRows: memoryPhotoRows, places: places, signedURLs: signedURLsByPath)
    }

    /// Memories from their rows, with their photos in order and the places they name.
    ///
    /// The one place a `Memory` is built from the database; `fetchCoupleState` had its own copy
    /// (CORE-24). A photo with no signed URL is left out rather than shown broken.
    static func makeMemories(rows: [MemoryRow], photoRows: [MemoryPhotoRow], places: [UUID: Place], signedURLs: [String: URL]) -> [Memory] {
        let photoRowsByMemory = Dictionary(grouping: photoRows, by: \.memoryId)
        return rows.map { row in
            let place = row.placeId.flatMap { places[$0] }
            let photoRows = (photoRowsByMemory[row.id] ?? []).sorted { $0.position < $1.position }
            let photos = photoRows.compactMap { photoRow -> MemoryPhoto? in
                guard let url = signedURLs[photoRow.photoPath] else { return nil }
                return MemoryPhoto(id: photoRow.id, path: photoRow.photoPath, url: url)
            }
            return Memory(
                id: row.id,
                title: row.title,
                place: place,
                date: row.occurredAt,
                note: row.note,
                photos: photos,
                tripID: row.tripId
            )
        }
    }

    /// Path includes a fresh photo id per upload (unlike the old single-photo `{coupleID}/{memoryID}.jpg`
    /// scheme) so a memory can hold more than one photo — the couple id stays the leading path
    /// segment since that's what the storage RLS policies key off.
    static func uploadMemoryPhoto(coupleID: UUID, memoryID: UUID, imageData: Data) async throws -> String {
        let path = "\(coupleID)/\(memoryID)/\(UUID().uuidString).jpg"
        try await R2Storage.upload(.memoryPhoto, path: path, data: imageData, contentType: "image/jpeg")
        return path
    }

    @discardableResult
    static func insertMemory(coupleID: UUID, memory: Memory, photoPaths: [String]) async throws -> [MemoryPhoto] {
        var placeID: UUID?
        if let place = memory.place {
            placeID = try await findOrCreatePlaceID(place)
        }
        try await supabase
            .from("memories")
            .insert(
                MemoryInsert(
                    id: memory.id,
                    coupleId: coupleID,
                    placeId: placeID,
                    title: memory.title,
                    note: memory.note,
                    occurredAt: memory.date
                )
            )
            .execute()

        return try await addMemoryPhotos(memoryID: memory.id, photoPaths: photoPaths, startingPosition: 0)
    }

    /// The fields of a memory somebody changed, and only those (`MemoryEdit`).
    static func updateMemory(_ edit: MemoryEdit) async throws {
        var placeID: Changed<UUID?>?
        let rows: [MemoryRow]
        if let place = edit.place {
            if let newPlace = place.value {
                placeID = Changed(value: try await findOrCreatePlaceID(newPlace))
            } else {
                placeID = Changed(value: nil)
            }
        }
        rows = try await supabase
            .from("memories")
            .update(
                MemoryUpdate(
                    placeId: placeID,
                    title: edit.title,
                    note: edit.note,
                    occurredAt: edit.date
                )
            )
            .eq("id", value: edit.memoryID)
            // `.select()` so the response carries the rows it touched. Without it a policy refusal
            // is indistinguishable from success — see `WriteAffectedNoRows`.
            .select()
            .execute()
            .value as [MemoryRow]
        guard !rows.isEmpty else { throw WriteAffectedNoRows() }
    }

    /// Appends photos to an existing memory (used both for the initial save and later edits),
    /// returning them with resolved signed URLs ready for local state.
    @discardableResult
    static func addMemoryPhotos(memoryID: UUID, photoPaths: [String], startingPosition: Int) async throws -> [MemoryPhoto] {
        guard !photoPaths.isEmpty else { return [] }
        let inserts = photoPaths.enumerated().map { index, path in
            MemoryPhotoInsert(memoryId: memoryID, photoPath: path, position: startingPosition + index)
        }
        let rows: [MemoryPhotoRow] = try await supabase
            .from("memory_photos")
            .insert(inserts)
            .select()
            .execute()
            .value

        let signedURLsByPath = await memoryPhotoSignedURLs(paths: rows.map(\.photoPath))
        return rows.sorted(by: { $0.position < $1.position }).compactMap { row in
            signedURLsByPath[row.photoPath].map { MemoryPhoto(id: row.id, path: row.photoPath, url: $0) }
        }
    }

    static func deleteMemoryPhoto(id: UUID, path: String) async throws {
        try await supabase.from("memory_photos").delete().eq("id", value: id).execute()
        await R2Storage.remove(.memoryPhoto, paths: [path])
    }

    /// `memory_photos` rows cascade-delete with the memory automatically; the underlying
    /// storage objects don't (storage isn't linked by a DB foreign key), so they're removed
    /// explicitly here using the paths the caller already has in local state.
    static func deleteMemory(id: UUID, photoPaths: [String]) async throws {
        try await supabase.from("memories").delete().eq("id", value: id).execute()
        if !photoPaths.isEmpty {
            await R2Storage.remove(.memoryPhoto, paths: photoPaths)
        }
    }
}
