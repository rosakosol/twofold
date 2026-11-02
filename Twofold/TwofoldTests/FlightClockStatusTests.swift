//
//  FlightClockStatusTests.swift
//  TwofoldTests
//
//  What a flight says about itself once its stored status has stopped being news.
//
//  A flight that is not being tracked never hears from the provider again, so its status stays at
//  whatever it was when it was saved. The list said "Departing shortly" under "Past flights" ten days
//  after it flew (FLT-8), the tracking screen offered to spend a monthly slot tracking it (FLT-10),
//  and the header's home-time line for a boarding flight anchored the arrival while the countdown
//  beside it counted to the departure (FLT-7).
//
//  Fixed instants, explicit zones: nothing here reads the clock or the simulator's zone.
//

import Testing
import Foundation
@testable import Twofold

struct FlightClockStatusTests {

    private static func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private let sfo = FlightAirport(iata: "SFO", city: "San Francisco", timezone: "America/Los_Angeles")
    private let mel = FlightAirport(iata: "MEL", city: "Melbourne", timezone: "Australia/Melbourne")

    /// UA60, San Francisco 11:20pm on 11 August to Melbourne the morning of the 13th — across both
    /// midnight and the date line, so the departure's own date is not the one the phone shows.
    private func ua60(
        status: FlightStatus = .scheduled,
        tracking: Bool = false,
        refreshed: Date? = nil,
        estimatedOut: Date? = nil
    ) -> Flight {
        Flight(
            faFlightID: "UAL60-1",
            flightNumberIATA: "UA60", airlineCode: "UA",
            origin: sfo, destination: mel,
            scheduledOut: Self.instant("2026-08-11T23:20:00-07:00"),
            scheduledIn: Self.instant("2026-08-13T07:35:00+10:00"),
            estimatedOut: estimatedOut,
            status: status,
            lastRefreshedAt: refreshed,
            trackingEnabled: tracking
        )
    }

    // MARK: - FLT-8: a flown flight whose status never moved

    @Test("an untracked flight still marked scheduled ten days after it flew says it flew")
    func untrackedFlownFlightIsNotDepartingShortly() {
        let now = Self.instant("2026-08-23T10:00:00+10:00")
        let flight = ua60()

        #expect(flight.displayStatus(at: now) == .landed)
        let summary = flight.countdownSummary(at: now)
        #expect(summary != "Departing shortly")
        #expect(summary.hasPrefix("Flew"), "got \(summary)")
        // The date it left San Francisco, the 11th, not the 12th the Melbourne-zoned phone was on.
        #expect(summary.contains("11"), "got \(summary)")
        #expect(!summary.contains("12"), "got \(summary)")
    }

    @Test("the pill for that flight says it landed, not that it is scheduled")
    func untrackedFlownFlightPill() {
        let now = Self.instant("2026-08-23T10:00:00+10:00")
        let pill = StatusPill(flight: ua60(), now: now)
        #expect(pill.text == FlightStatus.landed.displayLabel)
    }

    @Test("a stale flight stuck in the air is no longer in the Home carousel days later")
    func staleInAirFlightIsNotCurrentlyRelevant() {
        let now = Self.instant("2026-08-16T10:00:00+10:00")
        let flight = ua60(status: .inAir, tracking: false)
        #expect(!flight.isCurrentlyRelevant(at: now))
        #expect(!flight.isInProgress(at: now))
    }

    @Test("a tracked flight the provider still calls delayed keeps saying so past its old departure")
    func freshTrackedStatusIsTrusted() {
        // Eight minutes past the scheduled time, refreshed a minute ago: the provider's word stands.
        let now = Self.instant("2026-08-11T23:28:00-07:00")
        let flight = ua60(status: .delayed, tracking: true, refreshed: now.addingTimeInterval(-60))

        #expect(flight.displayStatus(at: now) == .delayed)
        #expect(flight.countdownSummary(at: now) == "Departing shortly")
    }

    @Test("a flight that landed this morning still reads in hours, not as a date")
    func recentArrivalStaysRelative() {
        let now = Self.instant("2026-08-13T08:05:00+10:00")
        let summary = ua60(status: .arrived, tracking: true, refreshed: now).countdownSummary(at: now)
        #expect(summary == "Arrived 30m ago")
    }

    // MARK: - FLT-7: the header's two lines describe the same moment

    @Test("a boarding flight's milestone is its departure, the same one the countdown counts to")
    func boardingMilestoneIsDeparture() {
        let now = Self.instant("2026-08-11T22:50:00-07:00")
        let flight = ua60(status: .boarding, tracking: true, refreshed: now)

        #expect(flight.countdownSummary(at: now).hasPrefix("Departs in"))
        #expect(flight.countdownMilestone(at: now) == flight.bestDeparture)
    }

    @Test("in the air, the milestone is the arrival")
    func inAirMilestoneIsArrival() {
        let now = Self.instant("2026-08-12T03:00:00-07:00")
        let flight = ua60(status: .inAir, tracking: true, refreshed: now)
        #expect(flight.countdownMilestone(at: now) == flight.bestArrival)
    }

    // MARK: - FLT-10: offering to track a flight that has already flown

    @Test("an untracked flight still marked scheduled is over once its arrival has passed")
    func flownScheduledFlightIsOver() {
        #expect(ua60().isOver(at: Self.instant("2026-08-13T09:00:00+10:00")))
    }

    @Test("an untracked flight that has not left yet is not over, and nor is one in the air")
    func futureAndAirborneFlightsAreNotOver() {
        #expect(!ua60().isOver(at: Self.instant("2026-08-11T12:00:00-07:00")))
        #expect(!ua60().isOver(at: Self.instant("2026-08-12T05:00:00-07:00")))
    }
}
