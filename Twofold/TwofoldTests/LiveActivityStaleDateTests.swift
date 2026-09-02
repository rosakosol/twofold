//
//  LiveActivityStaleDateTests.swift
//  TwofoldTests
//
//  When a Live Activity's card stops being allowed to assert what it last heard.
//
//  This is the only thing that re-renders the card at a chosen moment. It matters because
//  `Text(_, style: .relative)` keeps ticking on its own but the branch that wraps it doesn't get
//  re-evaluated — so a flight that had landed sat there reading "Arrives in 5 minutes" with the
//  five minutes growing. Reported live.
//

import Testing
import Foundation
@testable import Twofold

struct LiveActivityStaleDateTests {

    private func flight(
        scheduledIn: Date? = nil,
        estimatedIn: Date? = nil,
        scheduledOut: Date? = nil,
        estimatedOut: Date? = nil
    ) -> Flight {
        Flight(
            flightNumberIATA: "SQ208",
            origin: FlightAirport(iata: "MEL", icao: "YMML", name: nil, city: "Melbourne", timezone: nil, latitude: nil, longitude: nil, country: "Australia"),
            destination: FlightAirport(iata: "SIN", icao: "WSSS", name: nil, city: "Singapore", timezone: nil, latitude: nil, longitude: nil, country: "Singapore"),
            scheduledOut: scheduledOut,
            scheduledIn: scheduledIn,
            estimatedOut: estimatedOut,
            estimatedIn: estimatedIn
        )
    }

    private let arrival = Date(timeIntervalSince1970: 1_800_000_000)

    /// No grace period. Thirty minutes of it is what left the countdown inverting under the words
    /// "Arrives in" — the card can't be allowed to keep asserting an arrival that should already
    /// have happened.
    @MainActor
    @Test("the card goes stale when the flight was due, not later")
    func staleAtArrival() {
        let manager = LiveActivityManager.shared
        #expect(manager.staleDateForTesting(flight(scheduledIn: arrival)) == arrival)
    }

    /// The provider's own estimate beats the schedule — a flight running an hour late shouldn't be
    /// called stale an hour before it lands.
    @MainActor
    @Test("a live estimate wins over the printed schedule")
    func estimateBeatsSchedule() {
        let late = arrival.addingTimeInterval(3600)
        let manager = LiveActivityManager.shared
        #expect(manager.staleDateForTesting(flight(scheduledIn: arrival, estimatedIn: late)) == late)
    }

    /// With no arrival time at all there's nothing to be right about, so it falls back to a day
    /// past departure rather than never going stale.
    @MainActor
    @Test("no arrival time falls back to a day past departure")
    func fallsBackToDeparture() {
        let departure = arrival.addingTimeInterval(-8 * 3600)
        let manager = LiveActivityManager.shared
        #expect(manager.staleDateForTesting(flight(scheduledOut: departure)) == departure.addingTimeInterval(24 * 3600))
    }

    /// A flight with no times at all still has to expire, or the card asserts itself forever.
    @MainActor
    @Test("a flight with no times still goes stale eventually")
    func alwaysExpires() {
        let manager = LiveActivityManager.shared
        #expect(manager.staleDateForTesting(flight()) > .now)
    }
}
