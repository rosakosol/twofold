//
//  WidgetSnapshotStorageTests.swift
//  TwofoldTests
//
//  Whether a written snapshot can be read back.
//
//  Every Home Screen widget renders from `WidgetSnapshot.read()`, and both halves of the round
//  trip fail silently: `write` swallows an encode failure through `try?`, and `defaults` is an
//  optional that no-ops the whole write if the app-group suite can't be opened. Between them, a
//  snapshot that never lands looks exactly like a widget with nothing to show.
//

import Testing
import Foundation
@testable import Twofold

// Serialized: every test here writes to the same app-group UserDefaults key, so run in parallel
// they clear each other's state mid-test and report failures that are pure interference.
@Suite(.serialized)
struct WidgetSnapshotStorageTests {

    private func snapshot(
        progress: Double = 0.4,
        temperature: Double = 21
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            myID: UUID(),
            myName: "Alex",
            partnerName: "Sam",
            myCity: "Rome",
            partnerCity: "Melbourne",
            partnerTimeZoneIdentifier: "Australia/Melbourne",
            distanceLabel: "15,966 km",
            isSameCity: false,
            anniversaryDate: Date(timeIntervalSince1970: 1_600_000_000),
            subscriptionTier: "premium",
            nextFlight: flightInfo(progress: progress),
            trackedFlights: [flightInfo(progress: progress)],
            nextReunion: .init(departureDate: Date(timeIntervalSince1970: 1_800_000_000), destinationCity: "Rome", isReunionTrip: true),
            latestMemory: .init(id: UUID(), title: "Positano", date: Date(timeIntervalSince1970: 1_700_000_000)),
            partnerWeather: .init(symbolName: "sun.max.fill", temperatureC: temperature),
            relationshipStats: .init(memoryCount: 12, tripCount: 3),
            coupleID: UUID(),
            partnerID: UUID(),
            mySignedDrawingPadURL: URL(string: "https://example.com/mine.png"),
            partnerSignedDrawingPadURL: URL(string: "https://example.com/theirs.png"),
            writtenAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }

    private func flightInfo(progress: Double) -> WidgetSnapshot.FlightInfo {
        .init(
            id: UUID(), status: .inAir, originCity: "Melbourne", destinationCity: "Singapore",
            originCode: "MEL", destinationCode: "SIN",
            bestDeparture: Date(timeIntervalSince1970: 1_780_000_000),
            bestArrival: Date(timeIntervalSince1970: 1_780_030_000),
            delaySeconds: 600, flightNumber: "SQ208", progress: progress, travelerIsMe: true
        )
    }

    /// The whole contract: what the app writes, a widget can read.
    @Test func aFullSnapshotRoundTrips() throws {
        WidgetSnapshot.clear()
        WidgetSnapshot.write(snapshot())
        let read = try #require(WidgetSnapshot.read(), "Nothing was readable back — widgets would render empty")
        #expect(read.partnerName == "Sam")
        #expect(read.trackedFlights.count == 1)
        #expect(read.nextFlight?.flightNumber == "SQ208")
        WidgetSnapshot.clear()
    }

    /// The app group suite has to open at all. When it doesn't, `defaults?` optional-chains the
    /// write into a no-op and nothing anywhere reports a problem.
    @Test func theAppGroupSuiteIsReachable() throws {
        WidgetSnapshot.clear()
        WidgetSnapshot.write(snapshot())
        #expect(WidgetSnapshot.read() != nil, "UserDefaults(suiteName:) for the app group isn't usable from this target")
        WidgetSnapshot.clear()
    }

    /// JSONEncoder throws outright on a non-finite Double rather than writing null, and `write`
    /// swallows that with `try?` — so one bad number anywhere in the payload silently costs every
    /// widget its entire snapshot, not just the field it came from.
    @Test func aNonFiniteNumberDoesNotSilentlyLoseEverything() throws {
        WidgetSnapshot.clear()
        WidgetSnapshot.write(snapshot())
        let good = try #require(WidgetSnapshot.read())

        WidgetSnapshot.write(snapshot(progress: .nan))
        let after = try #require(WidgetSnapshot.read(), "A NaN wiped the snapshot entirely")
        // Either the NaN was sanitised on the way in, or the previous good snapshot survived.
        // What must never happen is `read()` returning nil because one Double was unencodable.
        #expect(after.partnerName == good.partnerName)
        WidgetSnapshot.clear()
    }
}

/// The other half of a blank widget: a snapshot that *is* written but never moves.
///
/// A Home Screen widget renders whatever the main app last wrote, and the main app only runs when
/// someone opens it. So a flight last seen as scheduled stayed "Scheduled" through boarding,
/// take-off and landing — the reported case was one sitting at Scheduled while it was in the air.
struct FlightStatusProjectionTests {

    private let departure = Date(timeIntervalSince1970: 1_780_000_000)
    private var arrival: Date { departure.addingTimeInterval(8 * 3600) }

    @Test("before departure, a scheduled flight is still scheduled")
    func beforeDepartureNothingChanges() {
        let now = departure.addingTimeInterval(-3600)
        #expect(FlightStatus.scheduled.projected(departure: departure, arrival: arrival, now: now) == .scheduled)
        #expect(FlightStatus.boarding.projected(departure: departure, arrival: arrival, now: now) == .boarding)
    }

    /// The reported case.
    @Test("past its departure time, a stale 'scheduled' reads as in the air")
    func afterDepartureItMovesOn() {
        let now = departure.addingTimeInterval(3600)
        #expect(FlightStatus.scheduled.projected(departure: departure, arrival: arrival, now: now) == .inAir)
        #expect(FlightStatus.boarding.projected(departure: departure, arrival: arrival, now: now) == .inAir)
        #expect(FlightStatus.delayed.projected(departure: departure, arrival: arrival, now: now) == .inAir)
    }

    @Test("past its arrival time, it reads as landed")
    func afterArrivalItLands() {
        let now = arrival.addingTimeInterval(600)
        #expect(FlightStatus.scheduled.projected(departure: departure, arrival: arrival, now: now) == .landed)
        #expect(FlightStatus.inAir.projected(departure: departure, arrival: arrival, now: now) == .landed)
    }

    /// Wheels-down is inferable from a schedule. Reaching the gate isn't, so a flight the provider
    /// already called `arrived` must not be walked back to `landed`.
    @Test("arrival at the gate is never invented, and never undone")
    func arrivedIsLeftAlone() {
        #expect(FlightStatus.arrived.projected(departure: departure, arrival: arrival, now: arrival.addingTimeInterval(600)) == .arrived)
    }

    /// A cancellation is a fact about the flight, not a position on a clock.
    @Test("terminal statuses are never moved by the clock")
    func terminalStatusesAreFacts() {
        let now = arrival.addingTimeInterval(3600)
        #expect(FlightStatus.cancelled.projected(departure: departure, arrival: arrival, now: now) == .cancelled)
        #expect(FlightStatus.diverted.projected(departure: departure, arrival: arrival, now: now) == .diverted)
        #expect(FlightStatus.landed.projected(departure: departure, arrival: arrival, now: now) == .landed)
    }

    /// The provider knowing more than the timestamps do must win — this only ever fills a gap.
    @Test("a status ahead of the schedule is not dragged backwards")
    func itOnlyEverMovesForward() {
        let beforeDeparture = departure.addingTimeInterval(-3600)
        #expect(FlightStatus.inAir.projected(departure: departure, arrival: arrival, now: beforeDeparture) == .inAir)
        #expect(FlightStatus.landingSoon.projected(departure: departure, arrival: arrival, now: beforeDeparture) == .landingSoon)
    }

    @Test("with no times to reason from, the stored status stands")
    func missingTimesChangeNothing() {
        #expect(FlightStatus.scheduled.projected(departure: nil, arrival: nil) == .scheduled)
        #expect(FlightStatus.scheduled.projected(departure: nil, arrival: arrival, now: departure) == .scheduled)
    }
}
