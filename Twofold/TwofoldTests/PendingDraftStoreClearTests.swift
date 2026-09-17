//
//  PendingDraftStoreClearTests.swift
//  TwofoldTests
//
//  Drafts written before pairing must not survive the account that drafted them.
//
//  `PendingTripStore` and `PendingMemoryStore` hold trips and memories — memories with their photo
//  bytes — that were created locally before a couple existed. Neither is scoped to a user: the
//  directory is one flat pile and `loadAll()` returns all of it, and `loadSignedInState` restores
//  it unconditionally. So the next account to sign in on the device picked up the previous one's
//  drafts, and `performAdopt` flushes pending drafts to the backend on pairing — which turned an
//  inherited draft into a write into somebody else's couple.
//
//  Neither store had a `clear()` at all.
//

import Foundation
import Testing
@testable import Twofold

@Suite("Pending drafts do not outlive the account that made them", .serialized)
struct PendingDraftStoreClearTests {

    @Test("A drafted trip is gone after clear()")
    func tripDraftsAreCleared() throws {
        let trip = Trip(
            id: UUID(),
            travelerIDs: [],
            origin: Place(city: "Melbourne", country: "Australia", latitude: -37.81, longitude: 144.96),
            destination: Place(city: "Tokyo", country: "Japan", latitude: 35.68, longitude: 139.65),
            departureDate: Date().addingTimeInterval(86_400),
            arrivalDate: Date().addingTimeInterval(864_000),
            category: .together,
            distanceKm: 8_159
        )
        PendingTripStore.save(trip)
        #expect(PendingTripStore.loadAll().contains { $0.id == trip.id })

        PendingTripStore.clear()

        #expect(PendingTripStore.loadAll().isEmpty)
    }

    /// The manifest persists whatever absolute URL `save` produced, and an app container's path
    /// contains a UUID that changes on reinstall or update. Rewriting the URL inside a saved
    /// manifest to a directory that does not exist is what that looks like from `loadAll`'s side.
    @Test("A draft written by a previous install still yields its photos")
    func photosSurviveAContainerChange() throws {
        PendingMemoryStore.clear()
        let memory = Memory(
            id: UUID(),
            title: "Drafted before an update",
            place: nil,
            date: Date(),
            note: "",
            photoSeed: 3,
            photos: []
        )
        let photo = Data([0xFF, 0xD8, 0xFF, 0xDB] + Array(repeating: 0x7A, count: 128))
        _ = PendingMemoryStore.save(memory: memory, photosData: [photo])

        // Point the saved manifest's photo URLs at a container that no longer exists, leaving the
        // photo files themselves where they are — exactly the state an update leaves behind.
        //
        // Two encodings have to be matched, and missing either makes this test pass against the
        // bug it exists to catch: the directory is "Application Support", whose space is
        // percent-encoded in the URL, and JSONEncoder escapes every forward slash as "\/".
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let realDirectory = support.appendingPathComponent("PendingMemories", isDirectory: true).absoluteString
        let asWrittenToJSON = realDirectory.replacingOccurrences(of: "/", with: "\\/")
        let manifest = support
            .appendingPathComponent("PendingMemories", isDirectory: true)
            .appendingPathComponent("\(memory.id.uuidString).json")

        var json = try String(contentsOf: manifest, encoding: .utf8)
        #expect(json.contains(asWrittenToJSON), "the manifest should hold an absolute file URL — that is the thing being tested")
        json = json.replacingOccurrences(
            of: asWrittenToJSON,
            with: "file:\\/\\/\\/var\\/mobile\\/Containers\\/Data\\/Application\\/00000000-DEAD-BEEF\\/Library\\/Application%20Support\\/PendingMemories\\/"
        )
        try json.write(to: manifest, atomically: true, encoding: .utf8)

        let restored = PendingMemoryStore.loadAll().first { $0.memory.id == memory.id }
        #expect(restored != nil, "the draft itself should still load")
        #expect(restored?.photosData.first == photo, "its photo bytes should still be found — this is what gets uploaded on pairing")
        #expect(restored?.memory.photos.first?.url.path.contains("PendingMemories") == true,
                "and the URL handed to the UI should point at a file that exists now")
    }

    @Test("A drafted memory and its photo bytes are gone after clear()")
    func memoryDraftsAreCleared() throws {
        let memory = Memory(
            id: UUID(),
            title: "Someone else's memory",
            place: nil,
            date: Date(),
            note: "",
            photoSeed: 1,
            photos: []
        )
        // A real JPEG-ish payload, so the photo file is actually written.
        let photo = Data([0xFF, 0xD8, 0xFF, 0xDB] + Array(repeating: 0x00, count: 64))
        _ = PendingMemoryStore.save(memory: memory, photosData: [photo])
        #expect(PendingMemoryStore.loadAll().contains { $0.memory.id == memory.id })

        PendingMemoryStore.clear()

        let remaining = PendingMemoryStore.loadAll()
        #expect(remaining.isEmpty)
        // The photo bytes specifically — a manifest gone but its pictures left behind would still
        // be the previous account's photographs sitting on disk.
        #expect(remaining.allSatisfy { $0.photosData.isEmpty })
    }
}
