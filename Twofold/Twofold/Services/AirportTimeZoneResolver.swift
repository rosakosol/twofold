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
    ///
    /// A lookup that *fails* caches nothing and is tried again next time. Recording a failure as
    /// "this airport has no timezone" is the bug this comment exists to prevent: the first thing
    /// that asks is the flight list, moments after sign-in on a cold start, and if that one query
    /// does not get through then every airport on it is written off for the life of the launch —
    /// the Add Flight screen then shows every departure in the phone's own timezone, and no amount
    /// of reopening it recovers, because nothing asks again.
    @discardableResult
    static func resolve(iataCodes codes: [String?]) async -> Bool {
        let wanted = Set(codes.compactMap { $0 }.filter { !$0.isEmpty }).subtracting(cache.keys)
        guard !wanted.isEmpty else { return false }

        guard let fetched = try? await fetch(Array(wanted)) else { return false }

        // Only now, with an answer in hand, is a blank worth remembering: these codes were asked
        // about and the table genuinely had nothing, so asking again on every redraw would be
        // pointless traffic.
        for code in wanted {
            cache[code] = fetched[code] ?? ""
        }
        return fetched.values.contains { !$0.isEmpty }
    }

    #if DEBUG
    /// Test seam: lets a test make a lookup fail, which is the case that matters and the one a real
    /// query will not do on demand.
    static var fetchOverride: (@Sendable ([String]) async throws -> [String: String])?
    static func resetForTesting() {
        cache = [:]
        fetchOverride = nil
    }
    #endif

    private static func fetch(_ codes: [String]) async throws -> [String: String] {
        #if DEBUG
        if let fetchOverride { return try await fetchOverride(codes) }
        #endif
        return try await FlightSearchIndex.timeZoneIdentifiers(forIATACodes: codes)
    }
}
