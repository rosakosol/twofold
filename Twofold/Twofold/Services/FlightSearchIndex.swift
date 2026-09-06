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
            guard let near else {
                let rows: [Airport] = try await supabase.from("airports").select(airportColumns)
                    .limit(limit)
                    .execute().value
                return Array(rows.filter { $0.id != excluding?.id }.prefix(limit))
            }
            return try await nearestAirports(to: near, excluding: excluding, limit: limit)
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

    // MARK: - What to show before anyone types

    /// The airports actually closest to a coordinate.
    ///
    /// This used to fetch the first 200 rows the table happened to return — no ordering, no
    /// geography — and rank *those* by distance. With ~6,000 airports in the table, "nearest to
    /// Melbourne" meant nearest among an arbitrary two hundred scattered across the planet, which
    /// is why the departure step opened on a list of airports nobody in Australia has heard of.
    ///
    /// Narrowing has to happen in the query. A latitude/longitude box does that with no PostGIS and
    /// no new index: fetch what is inside the box, then rank properly by great-circle distance,
    /// because a box is square and the world is not.
    static func nearestAirports(to coordinate: CLLocationCoordinate2D, excluding: Airport? = nil, limit: Int = 20) async throws -> [Airport] {
        // Two passes. The first is a tight box that covers a country and its neighbours, which is
        // where the answer is for anyone who lives near other people. The second is for the
        // genuinely remote — an island, a research station — where the nearest airport is a long
        // way off and a tight box comes back empty.
        for degrees in [8.0, 30.0] {
            let rows = try await airports(within: degrees, of: coordinate)
            let candidates = rows.filter { $0.id != excluding?.id }
            if candidates.count >= limit || degrees == 30.0 {
                return rankByProximity(candidates, near: coordinate, limit: limit)
            }
        }
        return []
    }

    /// Where someone is likely to be flying *to*: elsewhere in the departure's own country, never
    /// the airport down the road from the one they are leaving from.
    ///
    /// This used to be the same arbitrary slice of the table as everything else, so the destination
    /// step opened on airports picked at random from around the world. Two people apart mostly fly
    /// one route over and over, and it is a domestic one more often than not.
    ///
    /// Typing still searches the whole world. This is only what fills the list before they do.
    static func domesticDestinations(from departure: Airport, limit: Int = 20) async throws -> [Airport] {
        guard let country = departure.country, !country.isEmpty else {
            return try await nearestAirports(to: departure.coordinate, excluding: departure, limit: limit)
        }

        let rows: [Airport] = (try? await supabase.from("airports").select(airportColumns)
            .eq("country", value: country)
            .limit(1000)
            .execute().value) ?? []
        let candidates = rows.filter { $0.id != departure.id }

        // Two ways to say "not where you already are", because neither works everywhere.
        //
        // Timezone is the only sub-country division this table carries, and in Australia — where
        // this matters most — timezone *is* state: leaving Melbourne drops every Victorian airport
        // and leaves Sydney, Canberra, Hobart, Adelaide, Brisbane and Perth. But a country that
        // sits in one timezone loses all of itself that way. Measured against the real table,
        // dropping Europe/London leaves Heathrow with three domestic destinations: a private
        // airfield, an RAF base, and St Helena in the South Atlantic.
        //
        // So the timezone rule applies only where it leaves a real list behind, and a plain radius
        // covers the rest. 250km is about the reach of a drive — beyond it, flying is the point.
        let differentRegion = candidates.filter { $0.timeZoneIdentifier == nil || $0.timeZoneIdentifier != departure.timeZoneIdentifier }
        let farEnough = candidates.filter { Geo.distanceKm(departure.coordinate, $0.coordinate) > 250 }
        let chosen = differentRegion.count >= 5 ? differentRegion : farEnough

        // A city-state has no domestic anywhere to go. Nearest wins there, which for Singapore is
        // Johor Bahru and Batam — genuinely where you would fly.
        guard chosen.count >= 3 else {
            return try await nearestAirports(to: departure.coordinate, excluding: departure, limit: limit)
        }

        return rankAsDestinations(chosen, from: departure.coordinate, limit: limit)
    }

    /// Airports someone would actually fly to, before airstrips they would not.
    ///
    /// Sorting purely by distance buries Sydney under every regional strip that happens to be
    /// nearer — Tumut, Goulburn, Camden — and nobody flies interstate to Tumut to see their
    /// partner. The table has no passenger numbers and no size of any kind, so the ranking uses the
    /// two signals it does have: an airport named "International" is one that receives flights from
    /// elsewhere, and one with a named city serves somewhere people live.
    private static func rankAsDestinations(_ airports: [Airport], from origin: CLLocationCoordinate2D, limit: Int) -> [Airport] {
        func tier(_ airport: Airport) -> Int {
            let name = airport.name.lowercased()
            // Military fields are excluded from the top tier by name, not dropped: a few carry
            // "International" (Yuma MCAS among them) and would otherwise lead the list, but some
            // also take civilian flights, so they stay available further down.
            let isMilitary = ["raaf", "raf ", "mcas", "afb", " air base", "air force", "naval air", "army air"]
                .contains { name.contains($0) }
            if name.contains("international"), !isMilitary { return 0 }
            if airport.city?.isEmpty == false { return 1 }
            return 2
        }
        return airports
            .sorted {
                let (a, b) = (tier($0), tier($1))
                if a != b { return a < b }
                return Geo.distanceKm(origin, $0.coordinate) < Geo.distanceKm(origin, $1.coordinate)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// A latitude/longitude box, sized in degrees of latitude. Longitude degrees narrow towards the
    /// poles, so the box is widened by 1/cos(latitude) to stay roughly square on the ground —
    /// without that, a box around Reykjavik is a third as wide as the same box around Singapore.
    private static func airports(within degrees: Double, of coordinate: CLLocationCoordinate2D) async throws -> [Airport] {
        let latitudeSpan = degrees
        let longitudeSpan = min(180, degrees / max(0.15, cos(coordinate.latitude * .pi / 180)))

        var query = supabase.from("airports").select(airportColumns)
            .gte("latitude", value: coordinate.latitude - latitudeSpan)
            .lte("latitude", value: coordinate.latitude + latitudeSpan)

        // Skipped entirely for a box that wraps the antimeridian, where `longitude between low and
        // high` is false for every row on both sides of it. The latitude band alone still narrows
        // the query enormously, and the distance ranking below sorts out the rest.
        let low = coordinate.longitude - longitudeSpan
        let high = coordinate.longitude + longitudeSpan
        if low >= -180, high <= 180 {
            query = query.gte("longitude", value: low).lte("longitude", value: high)
        }

        return (try? await query.limit(1000).execute().value) ?? []
    }

    private static func rankByProximity(_ rows: [Airport], near: CLLocationCoordinate2D?, limit: Int) -> [Airport] {
        guard let near else { return Array(rows.prefix(limit)) }
        return rows
            .sorted { Geo.distanceKm(near, $0.coordinate) < Geo.distanceKm(near, $1.coordinate) }
            .prefix(limit)
            .map { $0 }
    }

    #if DEBUG
    /// Test seam. The ranking is the part with judgement in it and the part that was wrong; the
    /// queries around it need a network and a populated table, which a unit test has neither of.
    static func rankAsDestinationsForTesting(_ airports: [Airport], from origin: CLLocationCoordinate2D, limit: Int) -> [Airport] {
        rankAsDestinations(airports, from: origin, limit: limit)
    }
    #endif

    /// PostgREST's `or=(...)` filter list is comma/paren-delimited — strip characters that would
    /// otherwise break out of the filter syntax rather than percent-encoding them, since this is
    /// free-typed search text, not something that needs exact-match fidelity.
    private static func escaped(_ text: String) -> String {
        text.filter { $0 != "," && $0 != "(" && $0 != ")" && $0 != "*" }
    }
}
