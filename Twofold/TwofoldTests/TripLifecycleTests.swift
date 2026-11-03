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
            distanceKm: 8_000,
            flights: flights
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
        model.travel.trips = [underway]

        #expect(model.travel.upcomingTrips.map(\.id) == [underway.id])
        #expect(model.travel.pastTrips.isEmpty)
        #expect(model.travel.activeTrip?.id == underway.id)
    }

    // MARK: - Trips with flights attached (CORE-1 / FLT-1)
    //
    // A trip's flight used to count as "currently relevant" whenever it had not landed yet, so a
    // reunion next month with its flight attached read as under way today: Home said "You're
    // together now" and the globe drew the trip. These pin fixed instants in an explicit zone, so
    // they mean the same thing on any simulator.

    private static let melbourne = TimeZone(identifier: "Australia/Melbourne")!
    private static var melbourneCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = melbourne
        return calendar
    }

    private static func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func flight(
        status: FlightStatus,
        out: String, in arrival: String,
        actualOut: String? = nil,
        refreshed: String? = nil,
        tracking: Bool = true
    ) -> Flight {
        Flight(
            flightNumberIATA: "QF1", airlineCode: "QF",
            origin: FlightAirport(iata: "MEL", city: "Melbourne", timezone: "Australia/Melbourne"),
            destination: FlightAirport(iata: "LHR", city: "London", timezone: "Europe/London"),
            scheduledOut: Self.instant(out), scheduledIn: Self.instant(arrival),
            actualOut: actualOut.map(Self.instant),
            status: status,
            lastRefreshedAt: refreshed.map(Self.instant),
            trackingEnabled: tracking
        )
    }

    private func trip(from departure: String, to end: String, flights: [Flight]) -> Trip {
        Trip(
            travelerIDs: [traveler], origin: place("Melbourne"), destination: place("London"),
            departureDate: Self.instant(departure), arrivalDate: Self.instant(end),
            category: .reunion, distanceKm: 16_900, flights: flights
        )
    }

    @Test("a reunion next month with its flight attached is not under way today")
    func futureTripWithItsFlightIsNotActive() {
        let now = Self.instant("2026-11-02T09:00:00+11:00")
        let leg = flight(status: .scheduled, out: "2026-12-02T16:00:00+11:00", in: "2026-12-03T06:30:00Z")
        let trip = trip(from: "2026-12-02T00:00:00+11:00", to: "2026-12-20T00:00:00+11:00", flights: [leg])

        #expect(!leg.isInProgress(at: now))
        #expect(!trip.isActive(at: now, calendar: Self.melbourneCalendar))
    }

    @Test("a leg still in the air holds the trip open past midnight on its last day")
    func airborneLegOutranksTheDates() {
        // Twenty minutes past midnight after the final day, so the dates alone say it is over; the
        // plane has not landed, because it left late.
        let now = Self.instant("2026-12-21T00:20:00+11:00")
        let leg = flight(
            status: .inAir, out: "2026-12-20T16:00:00+11:00", in: "2026-12-20T23:50:00+11:00",
            actualOut: "2026-12-20T18:00:00+11:00", refreshed: "2026-12-21T00:18:00+11:00"
        )
        let trip = trip(from: "2026-12-02T00:00:00+11:00", to: "2026-12-20T00:00:00+11:00", flights: [leg])

        #expect(trip.isActive(at: now, calendar: Self.melbourneCalendar))
    }

    @Test("a leg that landed over a quarter of an hour ago no longer holds the trip open")
    func landedLegLetsTheTripEnd() {
        let now = Self.instant("2026-12-21T01:00:00+11:00")
        let leg = flight(
            status: .arrived, out: "2026-12-20T16:00:00+11:00", in: "2026-12-21T00:30:00+11:00",
            actualOut: "2026-12-20T16:05:00+11:00", refreshed: "2026-12-21T00:58:00+11:00"
        )
        let trip = trip(from: "2026-12-02T00:00:00+11:00", to: "2026-12-20T00:00:00+11:00", flights: [leg])

        #expect(!trip.isActive(at: now, calendar: Self.melbourneCalendar))
    }
}
