//
//  TrackedTripEntityTests.swift
//  TwofoldTests
//
//  The Trip Countdown widget's "Edit Widget" picker, and the countdown label both countdown
//  widgets read from.
//
//  The picker is populated by `TrackedTripQuery` from the shared snapshot, so a trip missing from
//  the snapshot is a trip nobody can choose — and there's no error when that happens, just an
//  option that isn't there.
//

import Testing
import Foundation
@testable import Twofold

@Suite(.serialized)
struct TrackedTripEntityTests {

    private func trip(_ city: String, id: UUID? = UUID(), inDays: Double = 30) -> WidgetSnapshot.ReunionInfo {
        .init(
            id: id,
            departureDate: Date(timeIntervalSince1970: 1_800_000_000).addingTimeInterval(inDays * 86_400),
            destinationCity: city,
            isReunionTrip: true
        )
    }

    private func snapshot(trips: [WidgetSnapshot.ReunionInfo]) -> WidgetSnapshot {
        WidgetSnapshot(
            myID: UUID(), myName: "Alex", partnerName: "Sam",
            myCity: "Rome", partnerCity: "Melbourne", partnerTimeZoneIdentifier: "Australia/Melbourne",
            distanceLabel: "15,966 km", isSameCity: false, anniversaryDate: nil,
            subscriptionTier: "premium", nextFlight: nil, trackedFlights: [],
            nextReunion: trips.first, upcomingTrips: trips,
            latestMemory: nil, partnerWeather: nil, relationshipStats: nil,
            coupleID: UUID(), partnerID: UUID(),
            mySignedDrawingPadURL: nil, partnerSignedDrawingPadURL: nil,
            writtenAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }

    // MARK: - What the picker offers

    @Test("every upcoming trip is offered, in the order the app sorted them")
    func allUpcomingTripsAreSelectable() async throws {
        WidgetSnapshot.write(snapshot(trips: [trip("Rome", inDays: 10), trip("Tokyo", inDays: 40), trip("Lisbon", inDays: 90)]))
        let offered = try await TrackedTripQuery().suggestedEntities()
        #expect(offered.map(\.destinationCity) == ["Rome", "Tokyo", "Lisbon"])
        WidgetSnapshot.clear()
    }

    /// A snapshot written before `ReunionInfo` carried an id has trips that can't be identified.
    /// They're dropped rather than offered, since selecting one could never be resolved back.
    @Test("a trip with no id isn't offered")
    func unidentifiableTripsAreSkipped() async throws {
        WidgetSnapshot.write(snapshot(trips: [trip("Rome"), trip("Tokyo", id: nil)]))
        let offered = try await TrackedTripQuery().suggestedEntities()
        #expect(offered.map(\.destinationCity) == ["Rome"])
        WidgetSnapshot.clear()
    }

    /// How the widget resolves a previously-picked trip back to something to display.
    @Test("a chosen trip is found again by its id")
    func aChosenTripResolvesBack() async throws {
        let chosen = UUID()
        WidgetSnapshot.write(snapshot(trips: [trip("Rome"), trip("Tokyo", id: chosen), trip("Lisbon")]))
        let matched = try await TrackedTripQuery().entities(for: [chosen])
        #expect(matched.map(\.destinationCity) == ["Tokyo"])
        WidgetSnapshot.clear()
    }

    @Test("nothing to offer when there are no trips")
    func noTripsMeansNoOptions() async throws {
        WidgetSnapshot.write(snapshot(trips: []))
        #expect(try await TrackedTripQuery().suggestedEntities().isEmpty)
        WidgetSnapshot.clear()
    }
}

/// The label both countdown widgets show. It counted only in hours and minutes, which is fine on
/// the day and absurd before it — a flight a week out read "196h 20m".
struct CountdownLabelTests {

    @Test("a countdown more than a day out is counted in days")
    func daysAppearBeyondTwentyFourHours() {
        #expect(TimeMath.compactDuration(8 * 86_400 + 4 * 3600) == "8d 4h")
        #expect(TimeMath.compactDuration(36 * 3600) == "1d 12h")
    }

    @Test("the last day before departure still counts in hours and minutes")
    func withinADayItStaysGranular() {
        #expect(TimeMath.compactDuration(2 * 3600 + 10 * 60) == "2h 10m")
        #expect(TimeMath.compactDuration(23 * 3600 + 59 * 60) == "23h 59m")
    }

    @Test("the final hour counts in minutes alone")
    func theLastHourIsMinutes() {
        #expect(TimeMath.compactDuration(45 * 60) == "45m")
        #expect(TimeMath.compactDuration(0) == "0m")
    }

    /// A departure that has already passed clamps rather than counting up or showing a minus sign.
    @Test("a passed departure clamps to zero")
    func negativeIntervalsClamp() {
        #expect(TimeMath.compactDuration(-5000) == "0m")
    }
}
