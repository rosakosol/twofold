//
//  BackendService+Places.swift
//  Twofold
//
//  Cities and places, found or created by the `find_or_create_place` RPC.
//

import Foundation
import Supabase

extension BackendService {

    // MARK: - Places

    private struct PlaceRow: Decodable {
        var id: UUID
        var city: String
        var country: String
        var iataCode: String?
        var latitude: Double
        var longitude: Double
        var timezone: String?

        enum CodingKeys: String, CodingKey {
            case id, city, country, latitude, longitude, timezone
            case iataCode = "iata_code"
        }

        func toPlace() -> Place {
            Place(id: id, city: city, country: country, iataCode: iataCode, latitude: latitude, longitude: longitude, timeZoneIdentifier: timezone)
        }
    }

    private struct PlaceInsert: Encodable {
        var city: String
        var country: String
        var iataCode: String?
        var latitude: Double
        var longitude: Double
        var timezone: String?

        enum CodingKeys: String, CodingKey {
            case city, country, latitude, longitude, timezone
            case iataCode = "iata_code"
        }
    }

    struct IDRow: Decodable {
        var id: UUID
    }

    /// Looks up a place by (city, country) — the table's unique constraint — inserting it
    /// if it isn't seeded yet. Returns the backend's row id, which almost never matches the
    /// id on the local `Place` struct (that one's just a client-side placeholder).
    private struct FindOrCreatePlaceParams: Encodable {
        var pCity: String
        var pCountry: String
        var pIataCode: String?
        var pLatitude: Double?
        var pLongitude: Double?
        var pTimezone: String?
        enum CodingKeys: String, CodingKey {
            case pCity = "p_city"
            case pCountry = "p_country"
            case pIataCode = "p_iata_code"
            case pLatitude = "p_latitude"
            case pLongitude = "p_longitude"
            case pTimezone = "p_timezone"
        }
    }

    /// Through an RPC rather than a select-then-insert on `places`.
    ///
    /// The table used to be `using (true)` for select and `with check (true)` for insert, with no
    /// owner column — so every signed-in user could read the street addresses and venues other
    /// couples had tagged memories at, and write unbounded rows into a shared gazetteer. Both
    /// halves of this function were why those policies had to be that wide: it read by (city,
    /// country) to honour the unique constraint, then inserted on a miss. Moving the pair
    /// server-side let the policies go entirely (20261110000700).
    ///
    /// Also fixes a race the client version had: two people adding a trip to the same new city at
    /// once both missed the select and one lost to the unique constraint. The RPC uses
    /// `on conflict do nothing` and re-reads.
    static func findOrCreatePlaceID(_ place: Place) async throws -> UUID {
        let id: UUID = try await supabase
            .rpc("find_or_create_place", params: FindOrCreatePlaceParams(
                pCity: place.city,
                pCountry: place.country,
                pIataCode: place.iataCode,
                pLatitude: place.latitude,
                pLongitude: place.longitude,
                pTimezone: place.timeZoneIdentifier
            ))
            .execute()
            .value
        return id
    }

    private struct PlacesByIDsParams: Encodable {
        var pIds: [UUID]
        enum CodingKeys: String, CodingKey { case pIds = "p_ids" }
    }

    /// Matches the RPC's own cap. Chunked here rather than raising, for the same reason
    /// `R2Storage.readURLs` chunks: a couple with a long history legitimately resolves more places
    /// than one call should carry, and that is not an error.
    private static let maxPlaceIDsPerRequest = 500

    static func fetchPlaces(ids: [UUID]) async throws -> [UUID: Place] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [:] }

        var places: [UUID: Place] = [:]
        for chunk in stride(from: 0, to: unique.count, by: maxPlaceIDsPerRequest).map({
            Array(unique[$0..<min($0 + maxPlaceIDsPerRequest, unique.count)])
        }) {
            let rows: [PlaceRow] = try await supabase
                .rpc("places_by_ids", params: PlacesByIDsParams(pIds: chunk))
                .execute()
                .value
            for row in rows { places[row.id] = row.toPlace() }
        }
        return places
    }
}
