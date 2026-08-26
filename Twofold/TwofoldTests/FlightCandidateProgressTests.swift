//
//  FlightCandidateProgressTests.swift
//  TwofoldTests
//
//  The status column on an Add Flight search result.
//
//  The bug these pin: the column only ever answered "is it in the air?" and "how long until it
//  leaves?", and drew nothing at all otherwise. Every flight that had already departed fell into
//  that gap — searching for one you took this morning returned a correct result with a blank space
//  where every other row has its status, which reads as the app failing to find it.
//

import Testing
import Foundation
@testable import Twofold

struct FlightCandidateProgressTests {

    /// A candidate departing/arriving at fixed offsets from `now`, so every case below reads as
    /// "three hours ago" rather than as two absolute timestamps to mentally subtract.
    private func candidate(
        status: String? = nil,
        departsIn: TimeInterval? = nil,
        arrivesIn: TimeInterval? = nil,
        cancelled: Bool? = nil,
        diverted: Bool? = nil,
        now: Date
    ) -> AeroFlightCandidate {
        var candidate = AeroFlightCandidate()
        candidate.identIata = "SQ208"
        candidate.status = status
        candidate.cancelled = cancelled
        candidate.diverted = diverted
        candidate.scheduledOut = departsIn.map { now.addingTimeInterval($0) }
        candidate.scheduledIn = arrivesIn.map { now.addingTimeInterval($0) }
        return candidate
    }

    private let now = Date(timeIntervalSince1970: 1_787_000_000)

    // MARK: - The reported gap

    @Test("a flight that departed today and has already landed says so")
    func landedTodayReportsHowLongAgo() throws {
        let flight = candidate(status: "arrived", departsIn: -8 * 3600, arrivesIn: -3 * 3600 - 12 * 60, now: now)
        let summary = try #require(flight.progressSummary(now: now))
        #expect(summary.label == "LANDED")
        #expect(summary.detail == "3h 12m ago")
        #expect(summary.isPast)
    }

    /// The same case with no status at all — a schedule-sourced candidate carries none, and its own
    /// times are enough to place it behind us.
    @Test("a schedule-only flight whose times have both passed still reads as landed")
    func statuslessPastFlightReadsAsLanded() throws {
        let flight = candidate(departsIn: -8 * 3600, arrivesIn: -3 * 3600, now: now)
        let summary = try #require(flight.progressSummary(now: now))
        #expect(summary.label == "LANDED")
        #expect(summary.detail == "3h 0m ago")
    }

    /// Departed but not yet arrived, with no status — arrival is checked first precisely so a
    /// flight with both behind it doesn't get filed here.
    @Test("a statusless flight that has left but not landed reads as departed")
    func statuslessInProgressFlightReadsAsDeparted() throws {
        let flight = candidate(departsIn: -2 * 3600, arrivesIn: 3 * 3600, now: now)
        let summary = try #require(flight.progressSummary(now: now))
        #expect(summary.label == "DEPARTED")
    }

    @Test("landed is never blank even with no arrival time to measure from")
    func landedWithoutArrivalTimeStillSaysLanded() throws {
        let flight = candidate(status: "landed", departsIn: -6 * 3600, now: now)
        let summary = try #require(flight.progressSummary(now: now))
        #expect(summary.label == "LANDED")
        #expect(summary.detail == nil)
    }

    // MARK: - What already worked, kept working

    @Test("an upcoming flight counts down to departure")
    func upcomingFlightCountsDown() throws {
        let flight = candidate(departsIn: 2 * 3600 + 10 * 60, now: now)
        let summary = try #require(flight.progressSummary(now: now))
        #expect(summary.label == "2h 10m")
        #expect(summary.symbol == nil)
        #expect(!summary.isPast)
    }

    @Test("a flight in the air says so, and how long is left")
    func inAirReportsTimeRemaining() throws {
        let flight = candidate(status: "in_air", departsIn: -2 * 3600, arrivesIn: 4 * 3600 + 30 * 60, now: now)
        let summary = try #require(flight.progressSummary(now: now))
        #expect(summary.label == "IN AIR")
        #expect(summary.detail == "lands in 4h 30m")
        #expect(!summary.isPast)
    }

    // MARK: - Terminal states

    @Test("a cancelled flight is named cancelled, whichever field says so")
    func cancelledIsReported() throws {
        let byStatus = try #require(candidate(status: "cancelled", departsIn: 3 * 3600, now: now).progressSummary(now: now))
        #expect(byStatus.label == "CANCELLED")

        // AeroAPI sets the boolean without always moving the status across.
        let byFlag = try #require(candidate(status: "scheduled", departsIn: 3 * 3600, cancelled: true, now: now).progressSummary(now: now))
        #expect(byFlag.label == "CANCELLED")
        #expect(byFlag.isPast)
    }

    @Test("a diverted flight is named diverted")
    func divertedIsReported() throws {
        let summary = try #require(candidate(status: "scheduled", departsIn: -3 * 3600, diverted: true, now: now).progressSummary(now: now))
        #expect(summary.label == "DIVERTED")
    }

    // MARK: - The one case that legitimately has nothing to say

    @Test("a candidate with no status and no times renders nothing rather than guessing")
    func nothingToSayStaysEmpty() {
        #expect(candidate(now: now).progressSummary(now: now) == nil)
    }
}
