//
//  TripLifecycleTests.swift
//  TwofoldTests
//
//  Whether a trip is ahead, under way, or over.
//
//  Three states, decided by two properties that between them drive the Trips list's Upcoming/Past
//  sections (`AppModel.pastTrips` is `!isUpcoming && !isActive`), the countdown badge in
//  `TripRowView`, the carousel card, and `AppModel.activeTrip`.
//
//  `isActive` used to ask only whether an attached flight was in the air, so `arrivalDate` was read
//  by nothing. A trip therefore stopped being upcoming when its departure day started and — with
//  no live flight to speak for it — was immediately Past: sorted under that heading and badged
//  with a done checkmark while the person was still away. Reported from a real device on the first
//  morning of a trip running from that day until 22 December.
//
//  Most trips here have no tracked flight at all, and one that does is only "currently relevant"
//  while airborne, which is a few hours of a months-long visit. So the dates have to decide it, and
//  these pin all three boundaries rather than only the reported one.
//

import Testing
import Foundation
@testable import Twofold

struct TripLifecycleTests {

    private let traveler = Person(name: "Alex", accentColor: Person.palette[0]).id

    private func place(_ city: String) -> Place {
        Place(id: UUID(), city: city, country: "Australia", iataCode: nil, latitude: 0, longitude: 0)
    }

    /// Days are offsets from *today*, resolved against the calendar rather than by adding 86,400s,
    /// so the fixtures mean the same thing across a daylight-saving boundary as the code does.
    private func trip(departsInDays: Int, endsInDays: Int, flights: [Flight] = []) -> Trip {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return Trip(
            travelerIDs: [traveler],
            origin: place("Melbourne"),
            destination: place("Tokyo"),
            departureDate: calendar.date(byAdding: .day, value: departsInDays, to: today)!,
            arrivalDate: calendar.date(byAdding: .day, value: endsInDays, to: today)!,
            category: .reunion,
            distanceKm: 8_000
        )
    }

    @Test("a trip that leaves today and ends in December is under way, not finished")
    func longTripStartingTodayIsActive() {
        // The reported case, at the point it was reported: departure day has begun, the end is
        // three months out. Before the fix this was `!isUpcoming && !isActive` — Past, done, tick.
        let trip = trip(departsInDays: 0, endsInDays: 91)

        #expect(trip.isActive)
        #expect(!trip.isUpcoming)
    }

    @Test("a trip is still under way on its final day")
    func finalDayIsStillActive() {
        // `arrivalDate` is a day the trip covers, not the instant it ends. Somebody flying home on
        // the 22nd is still away on the morning of the 22nd, and an exclusive comparison would
        // mark them done at midnight.
        let trip = trip(departsInDays: -6, endsInDays: 0)

        #expect(trip.isActive)
    }

    @Test("a trip is over once its final day has passed")
    func afterTheFinalDayItIsPast() {
        // The other edge: this is what has to keep working, or nothing ever leaves Upcoming.
        let trip = trip(departsInDays: -10, endsInDays: -1)

        #expect(!trip.isActive)
        #expect(!trip.isUpcoming)
    }

    @Test("a trip that has not left yet is upcoming and not active")
    func futureTripIsUpcomingOnly() {
        let trip = trip(departsInDays: 5, endsInDays: 12)

        #expect(trip.isUpcoming)
        #expect(!trip.isActive)
    }

    @Test("the Trips list files an under-way trip under Upcoming rather than Past")
    @MainActor
    func listsPlaceAnActiveTripCorrectly() {
        // Through `AppModel`, because the sections are what the person actually sees and the
        // property is only how they are computed.
        let model = AppModel()
        let underway = trip(departsInDays: 0, endsInDays: 91)
        model.trips = [underway]

        #expect(model.upcomingTrips.map(\.id) == [underway.id])
        #expect(model.pastTrips.isEmpty)
        #expect(model.activeTrip?.id == underway.id)
    }
}
