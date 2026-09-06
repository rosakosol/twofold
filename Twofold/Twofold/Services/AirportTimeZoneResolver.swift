//
//  AirportTimeZoneResolver.swift
//  Twofold
//
//  One place that knows what time it is at an airport.
//
//  AeroAPI's `/schedules` endpoint — the only source for a flight more than about two days out,
//  which is most of them — returns flat origin and destination codes with no airport object behind
//  them, so it supplies no timezone at either end. Everything downstream then has to render a
//  departure time in *some* zone, and every screen picked its own fallback: the device here, the
//  home city there. That is how one UA60 out of San Francisco read 11:20pm on one screen, 4:20pm
//  on another and 8:20am on a third, all from the same correct instant.
//
//  The `airports` reference table has the answer and is already public-read. This looks it up once
//  per code per launch and hands it to anyone who asks, so the fallback stops being a per-screen
//  decision.
//
//  Deliberately main-actor rather than an actor: every caller is a view or the view model, the
//  cache is a dictionary of short strings, and the only await anyone should be doing here is the
//  network fetch itself.
//

import Foundation

@MainActor
enum AirportTimeZoneResolver {
    private static var cache: [String: String] = [:]

    /// Cache only, no network — safe to call while building a view body.
    static func timeZone(forIATACode code: String?) -> TimeZone? {
        guard let code, !code.isEmpty else { return nil }
        return cache[code].flatMap(TimeZone.init(identifier:))
    }

    /// Fetches whatever isn't cached yet, in a single query. Returns whether anything new arrived,
    /// so a caller can avoid a redraw that would change nothing.
    @discardableResult
    static func resolve(iataCodes codes: [String?]) async -> Bool {
        let wanted = Set(codes.compactMap { $0 }.filter { !$0.isEmpty }).subtracting(cache.keys)
        guard !wanted.isEmpty else { return false }

        let fetched = await FlightSearchIndex.timeZoneIdentifiers(forIATACodes: Array(wanted))
        // Every code that was asked for is recorded, including the ones the table had nothing for.
        // Without that, an airport genuinely missing from the table is re-queried on every redraw
        // for the life of the app.
        for code in wanted {
            cache[code] = fetched[code] ?? ""
        }
        return fetched.values.contains { !$0.isEmpty }
    }
}
