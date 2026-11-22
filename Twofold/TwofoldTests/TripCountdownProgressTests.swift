//
//  TripCountdownProgressTests.swift
//  TwofoldTests
//
//  The ring around the Lock Screen trip countdown: where the wait starts, and how full it is.
//
//  The wait starts when the last trip before this one ended, so the ring measures the time since
//  you were last away together; with no earlier trip, when the couple connected.
//

import Testing
import Foundation
@testable import Twofold

struct TripCountdownProgressTests {

    private let traveler = Person(name: "Alex", accentColor: Person.palette[0]).id
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func day(_ offset: Double) -> Date { now.addingTimeInterval(offset * 86_400) }

    private func trip(from start: Double, to end: Double) -> Trip {
        let place = Place(id: UUID(), city: "Melbourne", country: "Australia", iataCode: nil, latitude: 0, longitude: 0)
        return Trip(
            travelerIDs: [traveler], origin: place, destination: place,
            departureDate: day(start), arrivalDate: day(end), category: .reunion, distanceKm: 0
        )
    }

    @Test("The wait starts when the latest earlier trip ended")
    func startsAtTheLastTripsEnd() {
        let next = trip(from: 22, to: 30)
        let trips = [trip(from: -90, to: -80), trip(from: -60, to: -50), next, trip(from: 40, to: 45)]
        #expect(WidgetSnapshotWriter.countdownStart(for: next, among: trips, connectedAt: day(-400)) == day(-50))
    }

    @Test("With no earlier trip, the wait starts when the couple connected")
    func startsWhenTheyConnected() {
        let next = trip(from: 22, to: 30)
        #expect(WidgetSnapshotWriter.countdownStart(for: next, among: [next], connectedAt: day(-10)) == day(-10))
    }

    @Test("Nothing to measure from: no earlier trip, and no connection date before departure")
    func noStart() {
        let next = trip(from: 22, to: 30)
        #expect(WidgetSnapshotWriter.countdownStart(for: next, among: [next], connectedAt: nil) == nil)
        #expect(WidgetSnapshotWriter.countdownStart(for: next, among: [next], connectedAt: day(25)) == nil)
    }

    private func info(departing: Double, start: Double?) -> WidgetSnapshot.ReunionInfo {
        WidgetSnapshot.ReunionInfo(
            id: UUID(), departureDate: day(departing), destinationCity: "Melbourne", isReunionTrip: true,
            untilPhrase: nil, countdownStart: start.map(day)
        )
    }

    @Test("The ring is as full as the share of the wait that's passed")
    func progress() {
        #expect(info(departing: 25, start: -75).countdownProgress(at: now) == 0.75)
        #expect(info(departing: 25, start: 0).countdownProgress(at: now) == 0)
    }

    @Test("The ring stays between empty and full")
    func clamped() {
        #expect(info(departing: -1, start: -10).countdownProgress(at: now) == 1)
        #expect(info(departing: 25, start: 5).countdownProgress(at: now) == 0)
        #expect(info(departing: 25, start: 30).countdownProgress(at: now) == nil)
        #expect(info(departing: 25, start: nil).countdownProgress(at: now) == nil)
    }
}
