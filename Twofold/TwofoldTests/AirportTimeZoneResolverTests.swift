//
//  AirportTimeZoneResolverTests.swift
//  TwofoldTests
//
//  Against the real `airports` table, because the whole point of this type is that the table has an
//  answer the flight provider didn't give us. A stub would assert that a dictionary lookup works.
//
//  Needs a network. It says so when it fails rather than passing quietly.
//

import Testing
import Foundation
@testable import Twofold

@MainActor
struct AirportTimeZoneResolverTests {

    /// The airport from the reported bug. Its departure read in the device's timezone because the
    /// candidate carried no zone of its own, so a flight leaving at 11:20pm showed as 4:20pm.
    @Test("SFO resolves to Pacific time")
    func resolvesSanFrancisco() async {
        await AirportTimeZoneResolver.resolve(iataCodes: ["SFO"])
        #expect(
            AirportTimeZoneResolver.timeZone(forIATACode: "SFO")?.identifier == "America/Los_Angeles",
            "got \(String(describing: AirportTimeZoneResolver.timeZone(forIATACode: "SFO"))) — needs a network"
        )
    }

    /// Both ends of a route in one query, which is the shape every caller uses.
    @Test("a whole route resolves at once")
    func resolvesBothEnds() async {
        await AirportTimeZoneResolver.resolve(iataCodes: ["SFO", "MEL", nil, ""])
        #expect(AirportTimeZoneResolver.timeZone(forIATACode: "SFO") != nil)
        #expect(AirportTimeZoneResolver.timeZone(forIATACode: "MEL") != nil)
    }

    /// Melbourne, specifically. The reference table records MEL as `Australia/Hobart` — a migration
    /// in this repo corrects it, and until that is deployed this is what the app will read back.
    /// Asserted on the offset rather than the name so the test passes either side of that deploy:
    /// the two zones have kept identical rules since 2008, so what a departure *displays* is right
    /// either way, which is exactly why the wrong name went unnoticed for so long.
    @Test("MEL resolves to Melbourne's clock, whatever it is named")
    func melbourneOffsetIsCorrect() async throws {
        await AirportTimeZoneResolver.resolve(iataCodes: ["MEL"])
        let resolved = try #require(AirportTimeZoneResolver.timeZone(forIATACode: "MEL"), "needs a network")
        let melbourne = TimeZone(identifier: "Australia/Melbourne")!
        let instant = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(
            resolved.secondsFromGMT(for: instant) == melbourne.secondsFromGMT(for: instant),
            "MEL resolved to \(resolved.identifier), which is not Melbourne's clock"
        )
    }

    /// The whole chain in one assertion, in the terms the bug was reported in: take the instant
    /// UA60 leaves, resolve SFO the way the search results screen now does, and render it. The two
    /// halves are asserted separately above and in `FlightTimeDisplayTests`; this is the one that
    /// fails if either of them stops meeting in the middle.
    @Test("UA60's departure renders as 11:20 pm once SFO is resolved")
    func endToEnd() async throws {
        await AirportTimeZoneResolver.resolve(iataCodes: ["SFO"])
        let sfo = try #require(AirportTimeZoneResolver.timeZone(forIATACode: "SFO"), "needs a network")

        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 1
        components.hour = 6
        components.minute = 20
        components.timeZone = TimeZone(identifier: "UTC")
        let departure = Calendar(identifier: .gregorian).date(from: components)!

        let rendered = departure.formatted(Date.FormatStyle(timeZone: sfo).hour().minute())
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .lowercased()
        #expect(rendered == "11:20 pm", "got \(rendered)")
    }

    /// Nothing to look up must not become a query.
    @Test("an empty request does nothing")
    func emptyRequestIsANoOp() async {
        #expect(await AirportTimeZoneResolver.resolve(iataCodes: []) == false)
        #expect(await AirportTimeZoneResolver.resolve(iataCodes: [nil, ""]) == false)
    }

    /// A code the table has never heard of must be remembered as unknown, not re-queried forever.
    /// Asserted through the second call reporting no news, which is the signal callers use to
    /// decide whether a redraw is worth doing.
    @Test("an unknown airport is asked about once")
    func unknownAirportsAreNotRetriedForever() async {
        _ = await AirportTimeZoneResolver.resolve(iataCodes: ["ZZZZ"])
        #expect(await AirportTimeZoneResolver.resolve(iataCodes: ["ZZZZ"]) == false)
        #expect(AirportTimeZoneResolver.timeZone(forIATACode: "ZZZZ") == nil)
    }
}
