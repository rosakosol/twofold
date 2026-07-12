//
//  MemoryLocationSearchCompleter.swift
//  Twofold
//
//  Live location search for memories — unlike `CitySearchCompleter` (locked to city-level
//  results for trip/home-city pickers), this allows full street addresses and points of
//  interest, since a memory's location is often a specific place, not just a city.
//
//  Deliberately NOT an NSObject/MKLocalSearchCompleterDelegate itself — see
//  CitySearchCompleter.swift's header comment for why (self-as-delegate-during-init on an
//  @Observable NSObject subclass is a known trigger for "invalid reuse after initialization
//  failure").
//

import Foundation
import MapKit
import Observation

@Observable
@MainActor
final class MemoryLocationSearchCompleter {
    private let completer: MKLocalSearchCompleter
    private var proxy: DelegateProxy?

    var results: [MKLocalSearchCompletion] = []

    var queryFragment: String = "" {
        didSet {
            completer.queryFragment = queryFragment
        }
    }

    init() {
        let completer = MKLocalSearchCompleter()
        completer.resultTypes = [.address, .pointOfInterest]
        self.completer = completer

        let proxy = DelegateProxy()
        self.proxy = proxy
        proxy.owner = self
        completer.delegate = proxy
    }

    fileprivate func handleResultsUpdate(_ results: [MKLocalSearchCompletion]) {
        self.results = results
    }

    fileprivate func handleFailure() {
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

    private final class DelegateProxy: NSObject, MKLocalSearchCompleterDelegate {
        weak var owner: MemoryLocationSearchCompleter?

        func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
            let results = completer.results
            Task { @MainActor [weak owner] in
                owner?.handleResultsUpdate(results)
            }
        }

        func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
            Task { @MainActor [weak owner] in
                owner?.handleFailure()
            }
        }
    }
}
