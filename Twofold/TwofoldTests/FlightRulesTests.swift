//
//  FlightRulesTests.swift
//  TwofoldTests
//
//  Rules every flight surface has to agree on, each decided in one place: when a running Live
//  Activity stays up (FLT-3), what counts as delayed (FLT-13), who is on the plane (FLT-14), and
//  the empty states that must not contradict what is on screen (FLT-28, 3-flights-NEW-2).
//

import Testing
import Foundation
@testable import Twofold

struct FlightRulesTests {

    private static func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private let me = Person(name: "Sam", accentColor: Person.palette[0])
    private let partner = Person(name: "Alex", accentColor: Person.palette[1])

    private func flight(
        status: FlightStatus = .scheduled,
        out: String = "2026-11-02T18:00:00+11:00",
        in arrival: String = "2026-11-02T19:25:00+11:00",
        tracking: Bool = true,
        travelerIDs: [UUID] = [],
        createdBy: UUID? = nil,
        tripID: UUID? = nil,
        departureDelaySeconds: Int? = nil,
        arrivalDelaySeconds: Int? = nil
    ) -> Flight {
        Flight(
            tripID: tripID, createdBy: createdBy, travelerIDs: travelerIDs,
            faFlightID: "QFA409-1",
            flightNumberIATA: "QF409", airlineCode: "QF",
            origin: FlightAirport(iata: "MEL", city: "Melbourne", timezone: "Australia/Melbourne"),
            destination: FlightAirport(iata: "SYD", city: "Sydney", timezone: "Australia/Sydney"),
            scheduledOut: Self.instant(out), scheduledIn: Self.instant(arrival),
            departureDelaySeconds: departureDelaySeconds, arrivalDelaySeconds: arrivalDelaySeconds,
            status: status,
            trackingEnabled: tracking
        )
    }

    // MARK: - FLT-3: a delay must not end the Live Activity

    @Test("a running card stays up when its flight turns delayed before take-off")
    func delayKeepsTheRunningCard() {
        let now = Self.instant("2026-11-02T17:20:00+11:00")
        let delayed = flight(status: .delayed, departureDelaySeconds: 40 * 60)

        #expect(delayed.keepsLiveActivity(at: now))
        // Starting is unchanged: a delayed flight nobody has a card for yet doesn't get one here.
        #expect(!delayed.startsLiveActivity(at: now))
    }

    @Test("but not for a delay days away, a flight no longer tracked, or one that has landed")
    func delayRuleIsBounded() {
        let now = Self.instant("2026-10-30T17:20:00+11:00")
        #expect(!flight(status: .delayed).keepsLiveActivity(at: now))
        #expect(!flight(status: .delayed, tracking: false).keepsLiveActivity(at: Self.instant("2026-11-02T17:20:00+11:00")))
        #expect(!flight(status: .landed).keepsLiveActivity(at: Self.instant("2026-11-02T19:30:00+11:00")))
    }

    @Test("every actively tracked status both starts and keeps a card")
    func activeStatusesStartAndKeep() {
        let now = Self.instant("2026-11-02T18:30:00+11:00")
        for status: FlightStatus in [.boarding, .departed, .inAir, .landingSoon] {
            #expect(flight(status: status).startsLiveActivity(at: now))
            #expect(flight(status: status).keepsLiveActivity(at: now))
        }
    }

    // MARK: - FLT-13: one delay threshold

    @Test("ten minutes late is late everywhere: the pill, the departure card and the sticker")
    func tenMinutesLateIsLateEverywhere() {
        let scheduled = Self.instant("2026-11-02T18:00:00+11:00")
        let estimated = scheduled.addingTimeInterval(10 * 60)

        let late = flight(status: .delayed, departureDelaySeconds: 600, arrivalDelaySeconds: 600)
        #expect(late.isDelayed)
        #expect(StatusPill(flight: late, now: scheduled.addingTimeInterval(-3600)).text == "Delayed 10 min")
        #expect(FlightDelay.deviation(scheduled: scheduled, actualOrEstimated: estimated) == .late(minutes: 10))
        #expect(FlightStickerData(flight: late, me: me, partner: partner).arrivalStatus == .delayed(minutes: 10))
    }

    @Test("within the threshold is on time everywhere, and early is early")
    func underTheThresholdIsOnTime() {
        let scheduled = Self.instant("2026-11-02T18:00:00+11:00")
        #expect(FlightDelay.deviation(scheduled: scheduled, actualOrEstimated: scheduled.addingTimeInterval(4 * 60)) == .onTime)
        #expect(FlightDelay.deviation(scheduled: scheduled, actualOrEstimated: scheduled.addingTimeInterval(-3 * 60)) == .early(minutes: 3))
        #expect(!flight(departureDelaySeconds: 240).isDelayed)
        #expect(FlightDelay.delayedMinutes(seconds: 240) == nil)
        #expect(FlightDelay.delayedMinutes(seconds: 360) == 6)
    }

    // MARK: - FLT-14: one rule for who is travelling

    @Test("a flight with nobody set takes its trip's travellers, then whoever added it")
    func travellerFallbacks() {
        let tripID = UUID()
        let older = flight(createdBy: me.id, tripID: tripID)
        let trip = Trip(
            id: tripID, travelerIDs: [partner.id],
            origin: Place(city: "Melbourne", country: "Australia", latitude: 0, longitude: 0),
            destination: Place(city: "Sydney", country: "Australia", latitude: 0, longitude: 0),
            departureDate: .distantPast, arrivalDate: .distantPast, category: .reunion, distanceKm: 700
        )

        #expect(older.travellerIDs(linkedTrip: trip) == [partner.id])
        #expect(older.travellerIDs(linkedTrip: nil) == [me.id])
        // Set explicitly, it wins over both.
        #expect(flight(travelerIDs: [partner.id], createdBy: me.id).travellerIDs(linkedTrip: nil) == [partner.id])
    }

    @Test("the widget and the share sticker read the same traveller the Live Activity does")
    func surfacesUseTheResolvedTravellers() {
        let older = flight(createdBy: me.id)
        let resolved = older.travellerIDs(linkedTrip: nil)
        let melbourne = TimeZone(identifier: "Australia/Melbourne")!

        let info = WidgetSnapshotWriter.flightInfo(for: older, currentUserID: me.id, travellerIDs: resolved, homeTimeZone: melbourne)
        #expect(info.travelerIsMe == true)
        #expect(FlightStickerData(flight: older, me: me, partner: partner, travellerIDs: resolved).travellerIsMe)
    }

    // MARK: - FLT-28: the Trips peek when every trip is behind you

    @Test("only past trips: the peek still offers a way to plan the next one")
    func pastTripsOnlyGetAHint() {
        #expect(TripsListView.tripsPeekHint(hasAnyTrip: true, hasUpcomingTrip: false) == .noneUpcoming)
        #expect(TripsListView.tripsPeekHint(hasAnyTrip: false, hasUpcomingTrip: false) == .firstTrip)
        #expect(TripsListView.tripsPeekHint(hasAnyTrip: true, hasUpcomingTrip: true) == nil)
    }

    // MARK: - 3-flights-NEW-2: a real flight with no time yet

    @Test("a chosen flight with no times doesn't say there is no flight or no trip")
    func flightWithoutTimesIsStillAFlight() {
        let now = Self.instant("2026-11-02T12:00:00+11:00")
        let info = WidgetSnapshot.FlightInfo(
            id: UUID(), status: .scheduled, originCity: "Melbourne", destinationCity: "Sydney",
            originCode: "MEL", destinationCode: "SYD", bestDeparture: nil, bestArrival: nil,
            delaySeconds: nil, flightNumber: "QF409", progress: 0, travelerIsMe: nil
        )
        let untimed = FlightWidgetTimeline.Moment(date: now, flight: info, status: .scheduled, isDeparted: false, target: nil, delaySeconds: nil, progress: 0)
        let none = FlightWidgetTimeline.Moment(date: now, flight: nil, status: nil, isDeparted: false, target: nil, delaySeconds: nil, progress: 0)

        #expect(!FlightCountdownCopy.caption(untimed).localizedCaseInsensitiveContains("no upcoming"))
        #expect(FlightCountdownCopy.headline(untimed) != "No flight")
        // And with no flight at all it still says so.
        #expect(FlightCountdownCopy.headline(none) == "No flight")
    }
}
