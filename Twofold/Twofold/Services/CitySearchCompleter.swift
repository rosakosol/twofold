//
//  CitySearchCompleter.swift
//  Twofold
//
//  Live city search backing CityMenuPicker. Deliberately doesn't request location
//  authorization — MKLocalSearchCompleter works fine off the typed query alone, and this
//  app has no other use for the user's current location.
//
//  Deliberately NOT an NSObject/MKLocalSearchCompleterDelegate itself — an @Observable class
//  that subclasses NSObject *and* assigns itself as a delegate from inside its own init() is a
//  known trigger for "invalid reuse after initialization failure" (self gets handed to the
//  completer before Swift/ObjC consider its own initialization fully settled). A small private,
//  non-Observable proxy object owns the delegate conformance instead.
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
@MainActor
final class CitySearchCompleter {
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
        completer.resultTypes = .address
        completer.addressFilter = MKAddressFilter(including: .locality)
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

    private final class DelegateProxy: NSObject, MKLocalSearchCompleterDelegate {
        weak var owner: CitySearchCompleter?

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
