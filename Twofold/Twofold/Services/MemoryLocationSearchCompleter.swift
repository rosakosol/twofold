//
//  MemoryLocationSearchCompleter.swift
//  Twofold
//
//  Live location search for memories — unlike `CitySearchCompleter` (locked to city-level
//  results for trip/home-city pickers), this allows full street addresses and points of
//  interest, since a memory's location is often a specific place, not just a city.
//

import Foundation
import MapKit
import Observation

@Observable
final class MemoryLocationSearchCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private let completer: MKLocalSearchCompleter

    var results: [MKLocalSearchCompletion] = []

    var queryFragment: String = "" {
        didSet {
            completer.queryFragment = queryFragment
        }
    }

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = self
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }

    /// Resolves a completion into a `Place` whose `city` field holds the full address/POI
    /// label (not a city name) — that's what memory location text should read back as.
    static func resolve(_ completion: MKLocalSearchCompletion) async throws -> Place {
        let request = MKLocalSearch.Request(completion: completion)
        let response = try await MKLocalSearch(request: request).start()

        guard let item = response.mapItems.first else {
            throw CitySearchError.noCityFound
        }

        let label = completion.title.isEmpty ? (item.name ?? "") : completion.title
        guard !label.isEmpty else { throw CitySearchError.noCityFound }

        return Place(
            city: label,
            country: item.placemark.country ?? item.addressRepresentations?.regionName ?? "",
            iataCode: nil,
            latitude: item.location.coordinate.latitude,
            longitude: item.location.coordinate.longitude,
            timeZoneIdentifier: item.timeZone?.identifier
        )
    }
}
