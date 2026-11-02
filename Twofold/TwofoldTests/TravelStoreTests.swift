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
        await model.addTrip(origin: melbourne, destination: tokyo, departureDate: .now, arrivalDate: .now, traveler: .you, category: .reunion)
        await model.addMemory(title: "Draft", place: nil, date: .now, note: "", imagesData: [Data([1, 2, 3])])
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
}
