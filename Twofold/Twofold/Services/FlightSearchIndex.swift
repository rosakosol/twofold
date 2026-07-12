//
//  FlightSearchIndex.swift
//  Twofold
//
//  Airport/airline suggestions backed by the `airports`/`airlines` Supabase tables (~6k and
//  ~1.1k rows respectively — a public reference dataset, RLS-readable by anon/authenticated,
//  see the airports_airlines_public_read migration) rather than a bundled client-side dataset.
//  Text matching (ilike, case-insensitive substring) happens in Postgres; proximity ranking for
//  airports happens client-side after fetching a candidate set, since the table has no PostGIS
//  extension to rank by distance in SQL.
//

import CoreLocation
import Foundation
import PostgREST
import Supabase

enum FlightSearchIndex {
    /// Matches against name/city/iata/icao. When `near` is supplied, a larger candidate set is
    /// pulled so client-side distance sorting has something meaningful to rank, then trimmed to
    /// `limit`.
    static func searchAirports(_ query: String, near: CLLocationCoordinate2D? = nil, limit: Int = 20) async throws -> [Airport] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let fetchLimit = near != nil ? max(limit * 5, 60) : limit

        var request = supabase.from("airports").select("iata,icao,name,city,country,latitude,longitude,timezone")
        if !q.isEmpty {
            let escaped = Self.escaped(q)
            request = request.or("name.ilike.*\(escaped)*,city.ilike.*\(escaped)*,iata.ilike.*\(escaped)*,icao.ilike.*\(escaped)*")
        }
        let rows: [Airport] = try await request.limit(fetchLimit).execute().value

        guard let near else { return Array(rows.prefix(limit)) }
        return rows
            .sorted { Geo.distanceKm(near, $0.coordinate) < Geo.distanceKm(near, $1.coordinate) }
            .prefix(limit)
            .map { $0 }
    }

    /// Matches against name/iata/icao. No location signal — airlines aren't geographically
    /// ranked.
    static func searchAirlines(_ query: String, limit: Int = 20) async throws -> [AirlineEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var request = supabase.from("airlines").select("iata,icao,name")
        if !q.isEmpty {
            let escaped = Self.escaped(q)
            request = request.or("name.ilike.*\(escaped)*,iata.ilike.*\(escaped)*,icao.ilike.*\(escaped)*")
        }
        let rows: [AirlineEntry] = try await request.limit(limit).execute().value
        return rows
    }

    /// PostgREST's `or=(...)` filter list is comma/paren-delimited — strip characters that would
    /// otherwise break out of the filter syntax rather than percent-encoding them, since this is
    /// free-typed search text, not something that needs exact-match fidelity.
    private static func escaped(_ text: String) -> String {
        text.filter { $0 != "," && $0 != "(" && $0 != ")" && $0 != "*" }
    }
}
