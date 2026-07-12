//
//  AirlineEntry.swift
//  Twofold
//
//  Decoded from the `airlines` Supabase table (~1.1k rows, public reference data — see
//  FlightSearchIndex for how this is searched). `iata` is the table's primary key.
//

import Foundation

struct AirlineEntry: Identifiable, Decodable, Hashable {
    var iata: String
    var icao: String?
    var name: String

    var id: String { iata }
}
