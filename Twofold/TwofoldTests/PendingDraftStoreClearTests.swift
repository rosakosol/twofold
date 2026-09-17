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
