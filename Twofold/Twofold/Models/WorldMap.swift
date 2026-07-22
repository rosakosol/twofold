//
//  WorldMap.swift
//  Twofold
//
//  Bundled, simplified (Douglas-Peucker, adaptive epsilon so small countries don't vanish)
//  Natural Earth 1:50m country boundaries — decoded once from `WorldBoundaries.json` and reused
//  by `WorldVisitedMapView` wherever the app renders a "countries you've been to" map. Each
//  polygon's points are pre-projected to a normalized 0...1 equirectangular box
//  (x = (lon+180)/360, y = (90-lat)/180 — a plain 2:1 rectangle, no trig needed at render time),
//  so rendering is just "scale to the view's own size."
//

import CoreGraphics
import Foundation

struct WorldCountryBoundary: Decodable {
    let name: String
    let isoA2: String
    /// Polygons → rings → points. A polygon's first ring is its outer boundary; any further
    /// rings in the same polygon are holes (e.g. an enclave like Lesotho inside South Africa).
    let polygons: [[[CGPoint]]]

    private enum CodingKeys: String, CodingKey {
        case name = "n"
        case isoA2 = "a2"
        case polygons = "p"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        isoA2 = try container.decode(String.self, forKey: .isoA2)
        let raw = try container.decode([[[[Double]]]].self, forKey: .polygons)
        polygons = raw.map { polygon in
            polygon.map { ring in
                ring.map { CGPoint(x: $0[0], y: $0[1]) }
            }
        }
    }
}

enum WorldMap {
    static let countries: [WorldCountryBoundary] = {
        guard
            let url = Bundle.main.url(forResource: "WorldBoundaries", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([WorldCountryBoundary].self, from: data)
        else { return [] }
        return decoded
    }()

    private static let byName: [String: WorldCountryBoundary] = Dictionary(
        uniqueKeysWithValues: countries.map { ($0.name, $0) }
    )

    /// Maps this app's free-text `Place.country` strings (sourced from the openflights-style
    /// `airports` table's `country` column) onto this dataset's Natural Earth admin names — most
    /// of the ~235 real values already match exactly (`Singapore`, `Australia`, `United Kingdom`),
    /// so this only needs entries for the real mismatches, found by diffing the two name lists.
    private static let nameAliases: [String: String] = [
        "Bahamas": "The Bahamas",
        "Burma": "Myanmar",
        "Cape Verde": "Cabo Verde",
        "Congo (Brazzaville)": "Republic of the Congo",
        "Congo (Kinshasa)": "Democratic Republic of the Congo",
        "Cote d'Ivoire": "Ivory Coast",
        "Czech Republic": "Czechia",
        "Hong Kong": "Hong Kong S.A.R.",
        "Macau": "Macao S.A.R",
        "Macedonia": "North Macedonia",
        "Micronesia": "Federated States of Micronesia",
        "Sao Tome and Principe": "São Tomé and Principe",
        "Serbia": "Republic of Serbia",
        "Swaziland": "eSwatini",
        "Tanzania": "United Republic of Tanzania",
        "United States": "United States of America",
        "Virgin Islands": "United States Virgin Islands",
    ]

    static func boundary(forCountryName name: String) -> WorldCountryBoundary? {
        byName[nameAliases[name] ?? name]
    }

    /// Resolves a list of `Place.country` strings to this dataset's own boundary names — the set
    /// `WorldVisitedMapView` checks membership against when filling in visited countries. A
    /// handful of very small territories (Gibraltar, Réunion, Wake Island, …) have no boundary of
    /// their own at this simplification level and are silently dropped rather than mismatched to
    /// their parent country.
    static func visitedNames<S: Sequence>(from countryNames: S) -> Set<String> where S.Element == String {
        Set(countryNames.compactMap { boundary(forCountryName: $0)?.name })
    }
}
