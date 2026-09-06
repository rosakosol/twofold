//
//  FlightTimeDisplayTests.swift
//  TwofoldTests
//
//  UA60, and the two separate reasons it read as 4:20pm.
//
//  It leaves San Francisco at 23:20 on 30 September. The stored instant was always right — 06:20Z —
//  and every wrong number on screen was that instant rendered in the wrong zone.
//
//  The first reason was data: a flight resolved from AeroAPI's `/schedules` endpoint carries no
//  airport timezone, so the detail cards had nothing to render in and fell back.
//
//  The second was a decision. The journey summary rendered both legs in the viewer's home city on
//  purpose, so a glance answered "when do I need to be ready". In Melbourne that turns 23:20 PDT
//  into 16:20 AEST, and the summary said 4:20pm for a flight whose boarding pass says 11:20pm.
//  Fixing the data alone would not have changed that number, which is what the arithmetic below
//  pins down.
//

import Testing
import Foundation
@testable import Twofold

struct FlightTimeDisplayTests {

    /// 23:20 on 30 September 2026 at SFO. PDT is UTC-7, so the instant is 06:20Z on 1 October.
    private var ua60Departure: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 1
        components.hour = 6
        components.minute = 20
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private let sanFrancisco = TimeZone(identifier: "America/Los_Angeles")!
    private let melbourne = TimeZone(identifier: "Australia/Melbourne")!

    /// Lowercased and with the space normalised, because neither is what these tests are about.
    /// The locale decides the case of "pm" — en_AU renders "11:20 pm" where en_US renders
    /// "11:20 PM" — and the formatter separates the two with U+202F, a narrow no-break space,
    /// which is invisibly not the space in a Swift string literal. Comparing raw output fails on
    /// two strings that look identical in the failure message.
    private func time(_ date: Date, in zone: TimeZone) -> String {
        Self.normalised(date.formatted(Date.FormatStyle(timeZone: zone).hour().minute()))
    }

    static func normalised(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .lowercased()
    }

    /// The number that has to be on screen.
    @Test("UA60 departs at 11:20 pm in San Francisco")
    func departureReadsInAirportTime() {
        #expect(time(ua60Departure, in: sanFrancisco) == "11:20 pm")
    }

    /// And the number that was on screen, which is the same instant in the viewer's home city.
    /// This is the negative control: it shows 4:20pm was never a wrong time, only a wrong frame,
    /// so nothing about the stored flight needed correcting.
    @Test("the same instant is 4:20 pm in Melbourne")
    func homeTimeIsWhatWasShown() {
        #expect(time(ua60Departure, in: melbourne) == "4:20 pm")
    }

    /// Home time still appears, underneath, because "when do I need to be ready" is a real question
    /// — it just isn't the departure time.
    @Test("home time is offered alongside, when it differs")
    func homeTimeLineIsShownWhenZonesDiffer() throws {
        let line = try #require(
            FlightTrackingView.homeTimeLine(for: ua60Departure, airportZone: sanFrancisco, homeZone: melbourne)
        )
        #expect(Self.normalised(line).contains("4:20 pm"), "got \(line)")
        #expect(line.hasSuffix("your time"), "got \(line)")
    }

    /// A domestic flight has nothing to convert, and "11:20 pm your time" under "11:20 pm" is
    /// noise on every row.
    @Test("no second line for a flight in your own timezone")
    func noHomeTimeLineWhenZonesMatch() {
        #expect(FlightTrackingView.homeTimeLine(for: ua60Departure, airportZone: melbourne, homeZone: melbourne) == nil)
    }

    /// Compared on offsets at that instant, not on zone names. Melbourne and Hobart are different
    /// identifiers naming the same clock, and Sydney is on daylight saving on dates when Brisbane
    /// is not — a name comparison gets both of those backwards.
    @Test("the comparison is on the clock, not the zone's name")
    func differentNamesSameClock() throws {
        let hobart = TimeZone(identifier: "Australia/Hobart")!
        #expect(
            FlightTrackingView.homeTimeLine(for: ua60Departure, airportZone: hobart, homeZone: melbourne) == nil,
            "Hobart and Melbourne are the same clock on this date — nothing to convert"
        )

        // Late January: Sydney observes daylight saving, Brisbane does not.
        var summer = DateComponents()
        summer.year = 2027
        summer.month = 1
        summer.day = 20
        summer.hour = 3
        summer.timeZone = TimeZone(identifier: "UTC")
        let inSummer = Calendar(identifier: .gregorian).date(from: summer)!
        let sydney = TimeZone(identifier: "Australia/Sydney")!
        let brisbane = TimeZone(identifier: "Australia/Brisbane")!
        #expect(
            FlightTrackingView.homeTimeLine(for: inSummer, airportZone: sydney, homeZone: brisbane) != nil,
            "Sydney is an hour ahead of Brisbane in January — that hour needs saying"
        )
    }
}
