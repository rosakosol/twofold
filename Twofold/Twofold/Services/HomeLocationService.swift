//
//  HomeLocationService.swift
//  Twofold
//
//  One-shot "use my current location" flow — requests `.whenInUse` authorization if needed,
//  takes a single location fix, then reverse-geocodes it into a `Place` (mirrors the shape
//  CitySearchCompleter.resolve(_:) already builds for text-search results). No continuous
//  tracking, no background usage — the app has no other use for location beyond this.
//
//  The fix itself never leaves the device: the `Place` this builds carries a city-level
//  coordinate, not the reading. See `cityLevelCoordinate(for:)` for why that matters more here
//  than it looks — the destination table is shared and world-readable.
//
//  Deliberately NOT an NSObject/CLLocationManagerDelegate itself — an @Observable class that
//  subclasses NSObject *and* assigns itself as a delegate from inside its own init() is a known
//  trigger for "invalid reuse after initialization failure" (self gets handed to CoreLocation
//  before Swift/ObjC consider its own initialization fully settled). A small private,
//  non-Observable proxy object owns the delegate conformance instead, and forwards callbacks
//  back to this object once it's fully constructed.
//

import CoreLocation
import Foundation

@Observable
@MainActor
final class HomeLocationService {
    enum State: Equatable {
        case idle
        case requesting
        case resolved(Place)
        case failed(String)
        case deniedOrRestricted
    }

    private let manager = CLLocationManager()
    private var proxy: DelegateProxy?
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var state: State = .idle

    init() {
        authorizationStatus = manager.authorizationStatus
        let proxy = DelegateProxy()
        self.proxy = proxy
        proxy.owner = self
        manager.delegate = proxy
    }

    func requestCurrentLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .requesting
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            state = .requesting
            manager.requestLocation()
        case .denied, .restricted:
            state = .deniedOrRestricted
        @unknown default:
            state = .deniedOrRestricted
        }
    }

    fileprivate func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            if state == .requesting {
                manager.requestLocation()
            }
        case .denied, .restricted:
            state = .deniedOrRestricted
        default:
            break
        }
    }

    fileprivate func handleLocationUpdate(_ locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task {
            do {
                let place = try await Self.resolvePlace(from: location)
                state = .resolved(place)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    fileprivate func handleFailure(_ error: Error) {
        state = .failed(error.localizedDescription)
    }

    private static func resolvePlace(from location: CLLocation) async throws -> Place {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks.first, let city = placemark.locality else {
            throw NSError(domain: "HomeLocationService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Couldn't determine your city from your location."])
        }
        let coordinate = cityLevelCoordinate(for: location)
        return Place(
            city: city,
            country: placemark.country ?? "",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneIdentifier: placemark.timeZone?.identifier
        )
    }

    /// The coordinate that leaves the device is the city's, never the fix itself.
    ///
    /// `public.places` is shared reference data, deduplicated on `(city, country)` and readable by
    /// every signed-in user — `places_select_authenticated ... using (true)`. So the row's
    /// latitude/longitude is whatever the *first* person to reach that city wrote, and passing the
    /// raw fix through made that a house-level position, published to everyone, for whoever
    /// happened to get there first. This is the one path that did it silently: the hourly
    /// foreground refresh in `RootView.refreshCurrentCityIfNeeded()` takes a fix with nobody
    /// asking. (The typed address and dropped pin in `MemoryLocationSearchView` also write
    /// coordinates, but those are a place the user deliberately named.)
    ///
    /// Nothing is lost by coarsening it, because the precision was never the reader's anyway:
    /// `findOrCreatePlaceID` returns the existing row whenever the city is already there, so every
    /// user after the first silently inherits the first one's coordinates. City-level is what the
    /// column has always meant in practice.
    ///
    /// Nearest bundled major city when there is one in range — a real city centre, unrelated to
    /// anybody's position. Otherwise the fix rounded to a ~11 km grid, which is the small-town and
    /// rural case the bundled list doesn't cover, and is coarse enough that the row can't point at
    /// a home.
    ///
    /// Internal rather than private so `HomeLocationCoarseningTests` can assert it directly; there
    /// is no other caller. `nonisolated` because it is a pure transform of its argument — the
    /// enclosing type is `@MainActor` for CoreLocation's sake, which this borrows no part of.
    nonisolated static func cityLevelCoordinate(for location: CLLocation) -> CLLocationCoordinate2D {
        if let major = Geo.nearestMajorCity(to: location.coordinate) {
            return major.coordinate
        }
        return CLLocationCoordinate2D(
            latitude: (location.coordinate.latitude * 10).rounded() / 10,
            longitude: (location.coordinate.longitude * 10).rounded() / 10
        )
    }

    /// Plain NSObject, no @Observable, no self-delegate-assignment-during-init — just forwards
    /// CLLocationManagerDelegate callbacks to `owner` on the main actor.
    private final class DelegateProxy: NSObject, CLLocationManagerDelegate {
        weak var owner: HomeLocationService?

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            let status = manager.authorizationStatus
            Task { @MainActor [weak owner] in
                owner?.handleAuthorizationChange(status)
            }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            Task { @MainActor [weak owner] in
                owner?.handleLocationUpdate(locations)
            }
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            Task { @MainActor [weak owner] in
                owner?.handleFailure(error)
            }
        }
    }
}
