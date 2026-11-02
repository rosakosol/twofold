//
//  FlightWidgetTimelineTests.swift
//  TwofoldTests
//
//  The two flight widgets render from a timeline worked out once, when WidgetKit asks for it, and
//  then walked through with nobody running the app. So every entry has to be right for its own
//  date, not for the moment the timeline was built: take-off, touchdown, and the flight after this
//  one all happen inside a single timeline (FLT-20, FLT-21, FLT-24).
//
//  What the widget shows at a time is the last entry at or before it, which is how WidgetKit
//  picks one; `shown(at:)` asks exactly that.
//

import Testing
import Foundation
@testable import Twofold

struct FlightWidgetTimelineTests {

    private static func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// QF409 Melbourne to Sydney, 18:00 to 19:25 Melbourne time.
    private static let departure = instant("2026-11-02T18:00:00+11:00")
    private static let arrival = instant("2026-11-02T19:25:00+11:00")
    /// The flight home two days later.
    private static let returnDeparture = instant("2026-11-04T09:00:00+11:00")
    private static let returnArrival = instant("2026-11-04T10:30:00+11:00")

    private static func flight(
        id: UUID = UUID(),
        number: String = "QF409",
        status: FlightStatus = .scheduled,
        destination: String = "Sydney",
        departure: Date? = Self.departure,
        arrival: Date? = Self.arrival,
        delaySeconds: Int? = nil
    ) -> WidgetSnapshot.FlightInfo {
        WidgetSnapshot.FlightInfo(
            id: id, status: status, originCity: "Melbourne", destinationCity: destination,
            originCode: "MEL", destinationCode: "SYD", bestDeparture: departure, bestArrival: arrival,
            delaySeconds: delaySeconds, flightNumber: number, progress: 0, travelerIsMe: false,
            originTimeZoneID: "Australia/Melbourne", destinationTimeZoneID: "Australia/Sydney"
        )
    }

    private static let outbound = flight()
    private static let home = flight(number: "QF432", destination: "Melbourne", departure: returnDeparture, arrival: returnArrival)

    private static func snapshot(_ flights: [WidgetSnapshot.FlightInfo]) -> WidgetSnapshot {
        WidgetSnapshot(
            myName: "Sam", partnerName: "Alex", subscriptionTier: WidgetTier.plus,
            nextFlight: flights.first, trackedFlights: flights, writtenAt: departure.addingTimeInterval(-86_400)
        )
    }

    private func shown(at date: Date, in plan: FlightWidgetTimeline.Plan) -> FlightWidgetTimeline.Moment? {
        plan.moments.last { $0.date <= date }
    }

    // MARK: - FLT-20: Flight Tracking after touchdown

    @Test("the countdown's label goes once there is nothing left to count")
    func noLabelOverALandedFlight() {
        let label = FlightWidgetTimeline.countdownLabel
        #expect(label(false, Self.departure, Self.departure.addingTimeInterval(-600)) == "Departs in")
        #expect(label(true, Self.arrival, Self.departure.addingTimeInterval(600)) == "Lands in")
        // "Lands in" over "Landed" read as a countdown to something that had happened.
        #expect(label(true, Self.arrival, Self.arrival.addingTimeInterval(300)) == nil)
        #expect(label(true, nil, Self.arrival) == nil)
    }

    @Test("a landed flight shows as landed, then gives way to the next flight fifteen minutes on")
    func trackingMovesOnToTheNextFlight() {
        let plan = FlightWidgetTimeline.trackingPlan(Self.snapshot([Self.outbound, Self.home]), from: Self.arrival.addingTimeInterval(-30 * 60))

        let justLanded = shown(at: Self.arrival.addingTimeInterval(5 * 60), in: plan)
        #expect(justLanded?.flight?.id == Self.outbound.id)
        #expect(justLanded?.status == .landed)

        let later = shown(at: Self.arrival.addingTimeInterval(16 * 60), in: plan)
        #expect(later?.flight?.id == Self.home.id, "the flight home, not the one that landed")
        #expect(later?.isDeparted == false)
        #expect(later?.target == Self.returnDeparture)
    }

    @Test("with no flight after it, a landed flight gives way to the empty state")
    func trackingEmptiesAfterTheLastFlight() {
        let plan = FlightWidgetTimeline.trackingPlan(Self.snapshot([Self.outbound]), from: Self.arrival.addingTimeInterval(-30 * 60))
        let later = shown(at: Self.arrival.addingTimeInterval(16 * 60), in: plan)
        #expect(later != nil)
        #expect(later?.flight == nil)
        #expect(later?.status == nil)
    }

    @Test("a flight landed long ago is not shown, and the widget does not reload every fifteen minutes for it")
    func trackingLongAfterTheLastFlight() {
        let now = Self.arrival.addingTimeInterval(3600)
        let plan = FlightWidgetTimeline.trackingPlan(Self.snapshot([Self.outbound]), from: now)
        #expect(plan.moments.first?.flight == nil)
        // Nothing on it changes with the clock any more; only a new snapshot changes it, and the
        // app reloads the widget when it writes one. The reload left is a safety net.
        #expect(plan.reloadAt == now.addingTimeInterval(6 * 3600))
    }

    @Test("every tracking entry is worked out for its own date")
    func trackingEntriesMatchTheirDates() {
        let plan = FlightWidgetTimeline.trackingPlan(Self.snapshot([Self.outbound, Self.home]), from: Self.departure.addingTimeInterval(-40 * 60))
        #expect(plan.moments.count > 1)
        for moment in plan.moments where moment.flight?.id == Self.outbound.id {
            #expect(moment.isDeparted == (moment.date >= Self.departure))
            #expect(moment.target == (moment.isDeparted ? Self.arrival : Self.departure))
        }
        #expect(plan.moments.allSatisfy { $0.date <= plan.reloadAt })
    }

    // MARK: - FLT-21: Flight Countdown across take-off and touchdown

    @Test("one countdown timeline counts to take-off, then on to touchdown")
    func countdownFlipsAtTakeOff() {
        let plan = FlightWidgetTimeline.countdownPlan(Self.snapshot([Self.outbound]), preferring: nil, from: Self.departure.addingTimeInterval(-30 * 60))

        for moment in plan.moments where moment.flight != nil {
            #expect(moment.isDeparted == (moment.date >= Self.departure), "phase at \(moment.date)")
        }
        let airborne = shown(at: Self.departure.addingTimeInterval(10 * 60), in: plan)
        #expect(airborne?.isDeparted == true)
        #expect(airborne.map(FlightCountdownCopy.headline) == "1h 15m")
        #expect(airborne.map(FlightCountdownCopy.caption) == "until Sydney")
    }

    @Test("the countdown's entries sit on the target's own minute marks")
    func countdownOnMinuteMarks() {
        let now = Self.departure.addingTimeInterval(-(20 * 60 + 17))
        let plan = FlightWidgetTimeline.countdownPlan(Self.snapshot([Self.outbound]), preferring: nil, from: now)
        let beforeTakeOff = plan.moments.dropFirst().filter { $0.date < Self.departure }
        #expect(beforeTakeOff.map(FlightCountdownCopy.headline) == (1...20).reversed().map { "\($0)m" })
        // At take-off itself it is already counting to touchdown.
        #expect(plan.moments.first { $0.date == Self.departure }.map(FlightCountdownCopy.headline) == "1h 25m")
    }

    @Test("after touchdown the countdown says landed, then moves on to the next flight")
    func countdownAfterTouchdown() {
        let plan = FlightWidgetTimeline.countdownPlan(Self.snapshot([Self.outbound, Self.home]), preferring: nil, from: Self.arrival.addingTimeInterval(-10 * 60))

        let landed = shown(at: Self.arrival.addingTimeInterval(60), in: plan)
        #expect(landed.map(FlightCountdownCopy.headline) == "Landed", "not \"0m\"")
        #expect(landed.map(FlightCountdownCopy.caption) == "in Sydney")
        #expect(landed.map { FlightCountdownCopy.accessoryLine($0, joiner: " in ") } == "QF409 · Landed")
        #expect(landed.flatMap(FlightCountdownCopy.circularLabel) == nil)
        #expect(landed.map(FlightCountdownCopy.circularSymbol) == FlightStatus.landed.icon)

        let next = shown(at: Self.arrival.addingTimeInterval(16 * 60), in: plan)
        #expect(next?.flight?.id == Self.home.id)
        #expect(next.map(FlightCountdownCopy.caption) == "until departure")
    }

    @Test("a picked flight that has landed gives way to the soonest one still to come")
    func pickedFlightFallsThrough() {
        let plan = FlightWidgetTimeline.countdownPlan(Self.snapshot([Self.outbound, Self.home]), preferring: Self.outbound.id, from: Self.arrival.addingTimeInterval(-10 * 60))
        #expect(shown(at: Self.arrival, in: plan)?.flight?.id == Self.outbound.id)
        #expect(shown(at: Self.arrival.addingTimeInterval(16 * 60), in: plan)?.flight?.id == Self.home.id)

        // A picked flight further out is kept while it is still to come.
        let picked = FlightWidgetTimeline.countdownPlan(Self.snapshot([Self.outbound, Self.home]), preferring: Self.home.id, from: Self.departure)
        #expect(picked.moments.allSatisfy { $0.flight?.id == Self.home.id })
    }

    @Test("the countdown never asks for a reload the moment its run ends with nothing new")
    func countdownReloadPolicy() {
        // Long after the last flight: one entry, and a reload hours away rather than `.atEnd`,
        // which asked again immediately and spent the budget on the same empty answer.
        let idle = Self.arrival.addingTimeInterval(3600)
        let plan = FlightWidgetTimeline.countdownPlan(Self.snapshot([Self.outbound]), preferring: nil, from: idle)
        #expect(plan.moments.map(FlightCountdownCopy.headline) == ["No flight"])
        #expect(plan.reloadAt == idle.addingTimeInterval(6 * 3600))

        // Mid-countdown: reload when the entries run out, and not before the last of them.
        let counting = FlightWidgetTimeline.countdownPlan(Self.snapshot([Self.outbound]), preferring: nil, from: Self.departure.addingTimeInterval(-30 * 60))
        #expect(counting.moments.allSatisfy { $0.date <= counting.reloadAt })
        #expect(counting.reloadAt > counting.moments.first!.date)
    }

    @Test("a cancelled or diverted flight says so instead of counting down")
    func countdownShowsCancelledAndDiverted() {
        let now = Self.departure.addingTimeInterval(-2 * 3600)
        for status: FlightStatus in [.cancelled, .diverted] {
            let plan = FlightWidgetTimeline.countdownPlan(Self.snapshot([Self.flight(status: status)]), preferring: nil, from: now)
            let first = plan.moments.first
            #expect(first.map(FlightCountdownCopy.headline) == status.displayLabel)
            #expect(first.map(FlightCountdownCopy.caption) == "flight to Sydney")
            #expect(first.map { FlightCountdownCopy.accessoryLine($0, joiner: " in ") } == "QF409 · \(status.displayLabel)")
            #expect(first.flatMap(FlightCountdownCopy.circularLabel) == nil)
            #expect(first.map(FlightCountdownCopy.circularSymbol) == status.icon)
        }
    }

    // MARK: - FLT-24: the delay is the leg still to come, per entry

    @Test("before take-off the badge shows the departure delay, after it the arrival delay")
    func delayFollowsThePhase() {
        // Written before departure, which is when the old single figure was fixed to the
        // departure delay for the rest of the flight.
        let scheduledOut = Self.instant("2036-03-01T18:00:00+11:00")
        let flight = Flight(
            faFlightID: "QFA409-2036",
            flightNumberIATA: "QF409", airlineCode: "QF",
            origin: FlightAirport(iata: "MEL", city: "Melbourne", timezone: "Australia/Melbourne"),
            destination: FlightAirport(iata: "SYD", city: "Sydney", timezone: "Australia/Sydney"),
            scheduledOut: scheduledOut, scheduledIn: scheduledOut.addingTimeInterval(85 * 60),
            departureDelaySeconds: 20 * 60, arrivalDelaySeconds: 8 * 60,
            status: .delayed,
            trackingEnabled: true
        )
        let info = WidgetSnapshotWriter.flightInfo(for: flight, currentUserID: UUID(), travellerIDs: [], homeTimeZone: TimeZone(identifier: "Australia/Melbourne")!)
        let snapshot = Self.snapshot([info])

        let before = FlightWidgetTimeline.trackingMoment(snapshot, at: scheduledOut.addingTimeInterval(-3600))
        let after = FlightWidgetTimeline.trackingMoment(snapshot, at: scheduledOut.addingTimeInterval(30 * 60))
        #expect(before.delaySeconds == 20 * 60)
        #expect(after.delaySeconds == 8 * 60)
    }

    @Test("a snapshot written before both delays were stored still shows its one figure")
    func legacyDelayStillReads() {
        let snapshot = Self.snapshot([Self.flight(delaySeconds: 900)])
        #expect(FlightWidgetTimeline.trackingMoment(snapshot, at: Self.departure.addingTimeInterval(-600)).delaySeconds == 900)
    }
}
