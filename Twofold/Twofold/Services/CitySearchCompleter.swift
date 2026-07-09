//
//  CitySearchCompleter.swift
//  Twofold
//
//  Live city search backing CityMenuPicker. Deliberately doesn't request location
//  authorization — MKLocalSearchCompleter works fine off the typed query alone, and this
//  app has no other use for the user's current location.
//

import Foundation
import MapKit
import Observation

enum CitySearchError: LocalizedError {
    case noCityFound

    var errorDescription: String? {
        switch self {
        case .noCityFound: "Couldn't find a city for that result."
        }
    }
}

@Observable
final class CitySearchCompleter: NSObject, MKLocalSearchCompleterDelegate {
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
        completer.resultTypes = .address
        completer.addressFilter = MKAddressFilter(including: .locality)
        completer.delegate = self
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }

    /// Resolves a completion (title/subtitle only) into a full `Place`, pulling city/country
    /// from `addressRepresentations`, coordinates from `location`, and the IANA timezone
    /// directly off `MKMapItem.timeZone` — no separate reverse-geocoding step needed.
    static func resolve(_ completion: MKLocalSearchCompletion) async throws -> Place {
        let request = MKLocalSearch.Request(completion: completion)
        let response = try await MKLocalSearch(request: request).start()

        guard let item = response.mapItems.first,
              let city = item.addressRepresentations?.cityName else {
            throw CitySearchError.noCityFound
        }

        return Place(
            city: city,
            country: item.addressRepresentations?.regionName ?? "",
            iataCode: nil,
            latitude: item.location.coordinate.latitude,
            longitude: item.location.coordinate.longitude,
            timeZoneIdentifier: item.timeZone?.identifier
        )
    }
}
