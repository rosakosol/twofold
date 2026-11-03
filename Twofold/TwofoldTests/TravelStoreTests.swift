//
//  TravelStoreTests.swift
//  TwofoldTests
//
//  The trips, flights and memories store, and that reset() leaves nothing of them, including the
//  drafts still waiting for a couple, for the next account.
//

import Foundation
import Testing
@testable import Twofold

// Nested under `PendingMemoryDiskTests` because these write the pending trip and memory stores.
extension PendingMemoryDiskTests {
@Suite("TravelStore", .serialized)
@MainActor
struct TravelStoreTests {

    private let melbourne = Place(city: "Melbourne", country: "Australia", latitude: -37.8136, longitude: 144.9631)
    private let tokyo = Place(city: "Tokyo", country: "Japan", latitude: 35.6762, longitude: 139.6503)

    @Test("reset() clears the lists and everything still waiting to be created")
    func resetClearsEverything() async {
        PendingTripStore.clear()
        PendingMemoryStore.clear()
        defer {
            PendingTripStore.clear()
            PendingMemoryStore.clear()
        }
        let model = AppModel()
        // Solo, so both are drafts held for a couple that does not exist yet.
        await model.travel.addTrip(origin: melbourne, destination: tokyo, departureDate: .now, arrivalDate: .now, traveler: .you, category: .reunion)
        await model.travel.addMemory(title: "Draft", place: nil, date: .now, note: "", imagesData: [Data([1, 2, 3])])
        model.flights = DemoData.flights
        let travel = model.travel
        #expect(!travel.pendingTripIDs.isEmpty)
        #expect(!travel.pendingMemoryIDs.isEmpty)
        #expect(!travel.pendingMemoryPhotoData.isEmpty)

        travel.reset()

        #expect(travel.trips.isEmpty)
        #expect(travel.memories.isEmpty)
        #expect(travel.flights.isEmpty)
        #expect(travel.pendingTripIDs.isEmpty)
        #expect(travel.pendingMemoryIDs.isEmpty)
        #expect(travel.pendingMemoryPhotoData.isEmpty)
        #expect(travel.pendingFlightCandidates.isEmpty)
    }

    @Test("Without its owner it does nothing rather than act for nobody")
    func noHost() async {
        let travel = TravelStore()
        travel.trips = []
        await travel.refreshTrips()
        await travel.refreshFlights()
        #expect(travel.trips.isEmpty)
    }

    @Test("reset() stops reading the couple's flights channel and closes it")
    func resetEndsTheFlightsChannel() async {
        let travel = TravelStore()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        var readerEnded = false
        continuation.onTermination = { _ in Task { @MainActor in readerEnded = true } }
        var closed = false
        travel.openCoupleFlightsFeed = { _ in (stream, { closed = true }) }
        await travel.startFlightsRealtimeSubscription(coupleID: UUID())
        #expect(travel.isFollowingCoupleFlights)

        travel.reset()

        #expect(!travel.isFollowingCoupleFlights)
        for _ in 0..<200 where !(closed && readerEnded) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(closed)
        #expect(readerEnded)
    }
}
}
