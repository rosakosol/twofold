//
//  Airport.swift
//  Twofold
//
//  Decoded from the `airports` Supabase table (~6k rows, public reference data — see
//  FlightSearchIndex for how this is searched). `iata` is the table's primary key, so it's
//  always present; `icao`/`city`/`country`/`timezone` are looser and can be null in the source
//  data.
//

import CoreLocation
import Foundation

struct Airport: Identifiable, Decodable, Hashable {
    var iata: String
    var icao: String?
    var name: String
    var city: String?
    var country: String?
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String?

    var id: String { iata }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Best-available code for AeroAPI lookups — prefers IATA (3-letter) since that's what
    /// `AeroFlightService`'s existing search functions expect. A handful of rows have an empty
    /// (not null) `iata` for airports with no IATA code assigned, hence the fallback to ICAO.
    var preferredCode: String? { iata.isEmpty ? icao : iata }

    /// City label with a sensible fallback when the source row has no city — used anywhere a
    /// short human-readable location is needed (e.g. route chips).
    var cityOrName: String { city ?? name }

    enum CodingKeys: String, CodingKey {
        case iata, icao, name, city, country, latitude, longitude
        case timeZoneIdentifier = "timezone"
    }
}
