//
//  FlightSearchIndex.swift
//  Twofold
//
//  Airport/airline suggestions backed by the `airports`/`airlines` Supabase tables (~6k and
//  ~1.1k rows respectively — a public reference dataset, RLS-readable by anon/authenticated,
//  see the airports_airlines_public_read migration) rather than a bundled client-side dataset.
//
//  Tiered so an exact code match always wins regardless of how many other rows merely contain
//  the query as a substring — e.g. typing "MEL" must surface Melbourne Intl (iata == "MEL")
//  first, not whichever airport with "mel" somewhere in its name Postgres happens to return
//  first. Tiers run as parallel requests (exact/prefix) with a third substring fallback only
//  fired if the first two didn't fill the requested limit, keeping the common case to ~2
//  round-trips. Proximity ranking (when `near` is supplied) is applied within each tier, not
//  across the merge, so an exact code match never gets buried under a "closer" partial match.
//

import CoreLocation
import Foundation
import PostgREST
import Supabase

enum FlightSearchIndex {
    private static let airportColumns = "iata,icao,name,city,country,latitude,longitude,timezone"
    private static let airlineColumns = "iata,icao,name"

    /// A curated, hand-picked list of ~30 major global carriers by real-world recognition/
    /// passenger volume — the `airlines` table has ~1.1k rows (including many tiny charter/
    /// regional operators) with no popularity signal of its own, so an empty-query default list
    /// needs this instead of an arbitrary Postgres row order.
    private static let topAirlineIATACodes: [String] = [
        "AA", "DL", "UA", "WN", "EK", "QR", "SQ", "LH", "AF", "BA",
        "KL", "TK", "CX", "QF", "NH", "JL", "KE", "CZ", "MU", "CA",
        "6E", "AI", "LA", "AC", "FR", "U2", "EY", "TG", "MH", "VS",
    ]

    static func searchAirports(_ query: String, near: CLLocationCoordinate2D? = nil, excluding: Airport? = nil, limit: Int = 20) async throws -> [Airport] {
        let q = query.trimmingCharacters(in: .whitespaces)

        guard !q.isEmpty else {
            let rows: [Airport] = try await supabase.from("airports").select(airportColumns)
                .limit(near != nil ? 200 : limit)
                .execute().value
            let ranked = rankByProximity(rows.filter { $0.id != excluding?.id }, near: near, limit: limit)
            return ranked
        }

        let escaped = Self.escaped(q)

        async let exactCodeRows: [Airport] = (try? await supabase.from("airports").select(airportColumns)
            .or("iata.ilike.\(escaped),icao.ilike.\(escaped)")
            .limit(5)
            .execute().value) ?? []

        async let prefixRows: [Airport] = (try? await supabase.from("airports").select(airportColumns)
            .or("iata.ilike.\(escaped)*,icao.ilike.\(escaped)*,name.ilike.\(escaped)*,city.ilike.\(escaped)*")
            .limit(limit * 3)
            .execute().value) ?? []

        var seen = Set<String>()
        if let excluding { seen.insert(excluding.id) }
        var merged: [Airport] = []
        func append(_ rows: [Airport]) {
            for airport in rankByProximity(rows, near: near, limit: rows.count) where !seen.contains(airport.id) {
                seen.insert(airport.id)
                merged.append(airport)
            }
        }

        append(await exactCodeRows)
        append(await prefixRows)

        if merged.count < limit {
            let substringRows: [Airport] = (try? await supabase.from("airports").select(airportColumns)
                .or("name.ilike.*\(escaped)*,city.ilike.*\(escaped)*")
                .limit(limit * 3)
                .execute().value) ?? []
            append(substringRows)
        }

        return Array(merged.prefix(limit))
    }

    static func searchAirlines(_ query: String, limit: Int = 20) async throws -> [AirlineEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)

        guard !q.isEmpty else {
            let filter = topAirlineIATACodes.map { "iata.eq.\($0)" }.joined(separator: ",")
            let rows: [AirlineEntry] = try await supabase.from("airlines").select(airlineColumns)
                .or(filter)
                .limit(topAirlineIATACodes.count)
                .execute().value
            let order = Dictionary(uniqueKeysWithValues: topAirlineIATACodes.enumerated().map { ($1, $0) })
            return rows.sorted { (order[$0.iata] ?? .max) < (order[$1.iata] ?? .max) }
        }

        let escaped = Self.escaped(q)

        async let exactCodeRows: [AirlineEntry] = (try? await supabase.from("airlines").select(airlineColumns)
            .or("iata.ilike.\(escaped),icao.ilike.\(escaped)")
            .limit(10)
            .execute().value) ?? []

        async let prefixRows: [AirlineEntry] = (try? await supabase.from("airlines").select(airlineColumns)
            .or("iata.ilike.\(escaped)*,icao.ilike.\(escaped)*,name.ilike.\(escaped)*")
            .limit(limit * 3)
            .execute().value) ?? []

        var seen = Set<String>()
        var merged: [AirlineEntry] = []
        func append(_ rows: [AirlineEntry]) {
            for entry in rows where !seen.contains(entry.id) {
                seen.insert(entry.id)
                merged.append(entry)
            }
        }

        append(await exactCodeRows)
        append(await prefixRows)

        if merged.count < limit {
            let substringRows: [AirlineEntry] = (try? await supabase.from("airlines").select(airlineColumns)
                .or("name.ilike.*\(escaped)*")
                .limit(limit * 3)
                .execute().value) ?? []
            append(substringRows)
        }

        return Array(merged.prefix(limit))
    }

    private static func rankByProximity(_ rows: [Airport], near: CLLocationCoordinate2D?, limit: Int) -> [Airport] {
        guard let near else { return Array(rows.prefix(limit)) }
        return rows
            .sorted { Geo.distanceKm(near, $0.coordinate) < Geo.distanceKm(near, $1.coordinate) }
            .prefix(limit)
            .map { $0 }
    }

    /// PostgREST's `or=(...)` filter list is comma/paren-delimited — strip characters that would
    /// otherwise break out of the filter syntax rather than percent-encoding them, since this is
    /// free-typed search text, not something that needs exact-match fidelity.
    private static func escaped(_ text: String) -> String {
        text.filter { $0 != "," && $0 != "(" && $0 != ")" && $0 != "*" }
    }
}
