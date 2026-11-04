//
//  LongestGapTests.swift
//  TwofoldTests
//
//  Stats' "Longest gap" counts only time apart that has already happened.
//
//  It used to measure between every reunion on the calendar, planned ones included, so a trip
//  booked for next spring stretched the "longest gap" into a future nobody had lived yet. And it
//  never counted the stretch a couple was in the middle of: three months apart since the last
//  visit read as whatever the gap between two older trips had been. With fewer than two reunions it
//  fell back to the whole time since connecting, ignoring the one visit that had broken it up.
//
//  The rule now: gaps between reunions that have started, the stretch before the first one (for a
//  long-distance couple, counted from when they connected), and the stretch since the last one —
//  nothing at all while a reunion is under way.
//

import Foundation
import Testing
@testable import Twofold

@Suite("Longest gap counts only time apart that has happened")
@MainActor
struct LongestGapTests {

    private static let melbourne = Place(city: "Melbourne", country: "Australia", latitude: -37.8136, longitude: 144.9631, timeZoneIdentifier: "Australia/Melbourne")
    private static let rome = Place(city: "Rome", country: "Italy", latitude: 41.9028, longitude: 12.4964, timeZoneIdentifier: "Europe/Rome")

    /// `days` calendar days from now, at the current time of day — so whole-day offsets survive a
    /// daylight-saving change in between.
    private static func day(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: .now)!
    }

    private static func couple(longDistance: Bool, connectedDaysAgo: Int? = nil) -> Couple {
        var couple = CoupleSession.placeholderCouple
        couple.partnerA.homeCity = melbourne
        couple.partnerB.homeCity = longDistance ? rome : melbourne
        couple.connectedAt = connectedDaysAgo.map { day(-$0) }
        return couple
    }

    private static func reunion(from start: Int, to end: Int) -> Trip {
        Trip(
            travelerIDs: [], origin: melbourne, destination: rome,
            departureDate: day(start), arrivalDate: day(end),
            category: .reunion, distanceKm: 15_000
        )
    }

    private static func longestGap(_ couple: Couple, _ trips: [Trip]) -> Int? {
        RelationshipMilestoneStats(couple: couple, trips: trips, memories: []).longestSeparationDays
    }

    @Test("a reunion still to come is not part of any gap")
    func futureReunionIsIgnored() {
        // Connected five days before the one visit so far; the next is booked ten days out. The
        // hundred days from the last visit to the planned one haven't all happened — ninety have.
        let trips = [Self.reunion(from: -100, to: -90), Self.reunion(from: 10, to: 20)]
        #expect(Self.longestGap(Self.couple(longDistance: true, connectedDaysAgo: 105), trips) == 90)
    }

    @Test("the stretch since the last reunion counts, and can be the longest")
    func currentStretchBeatsPastGaps() {
        // Past gaps of 5 (connecting to the first visit) and 90 (between visits); 195 since.
        let trips = [Self.reunion(from: -300, to: -290), Self.reunion(from: -200, to: -195)]
        #expect(Self.longestGap(Self.couple(longDistance: true, connectedDaysAgo: 305), trips) == 195)
    }

    @Test("while a reunion is under way, the current gap is nothing")
    func reunionInProgress() {
        // Thirty-seven days from connecting to this visit, which began three days ago. Not forty:
        // they are together now.
        let trips = [Self.reunion(from: -3, to: 4)]
        #expect(Self.longestGap(Self.couple(longDistance: true, connectedDaysAgo: 40), trips) == 37)
    }

    @Test("overlapping reunions are measured from the latest return, not the previous trip's")
    func overlappingReunions() {
        // A long visit, a short trip inside it, then one under way now. Apart only from day -50
        // (the long visit's end) to day -40.
        let trips = [
            Self.reunion(from: -100, to: -50),
            Self.reunion(from: -80, to: -70),
            Self.reunion(from: -40, to: 5),
        ]
        #expect(Self.longestGap(Self.couple(longDistance: true), trips) == 10)
    }

    @Test("long distance with no reunions yet counts from connecting until now")
    func noReunionsLongDistance() {
        let other = Trip(
            travelerIDs: [], origin: Self.melbourne, destination: Self.rome,
            departureDate: Self.day(-20), arrivalDate: Self.day(-10),
            category: .solo, distanceKm: 15_000
        )
        #expect(Self.longestGap(Self.couple(longDistance: true, connectedDaysAgo: 50), [other]) == 50)
    }

    @Test("a couple in one city with no reunions has no gap to show")
    func noReunionsSameCity() {
        #expect(Self.longestGap(Self.couple(longDistance: false, connectedDaysAgo: 50), []) == nil)
    }

    @Test("one past reunion splits the time since connecting in two")
    func exactlyOnePastReunion() {
        // Forty days before it, fifty since. Not the hundred since connecting.
        let trips = [Self.reunion(from: -60, to: -50)]
        #expect(Self.longestGap(Self.couple(longDistance: true, connectedDaysAgo: 100), trips) == 50)
    }

    /// A couple who share a home city now: the gaps between their logged reunions still happened,
    /// but neither the time before the first nor the time since the last is time apart.
    @Test("a couple in one city counts only between reunions")
    func sameCityCountsOnlyBetweenReunions() {
        let trips = [Self.reunion(from: -300, to: -295), Self.reunion(from: -260, to: -255)]
        #expect(Self.longestGap(Self.couple(longDistance: false, connectedDaysAgo: 400), trips) == 35)
    }
}
