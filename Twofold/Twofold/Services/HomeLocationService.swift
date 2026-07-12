//
//  HomeLocationService.swift
//  Twofold
//
//  One-shot "use my current location" flow — requests `.whenInUse` authorization if needed,
//  takes a single location fix, then reverse-geocodes it into a `Place` (mirrors the shape
//  CitySearchCompleter.resolve(_:) already builds for text-search results). No continuous
//  tracking, no background usage — the app has no other use for location beyond this.
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
        return Place(
            city: city,
            country: placemark.country ?? "",
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timeZoneIdentifier: placemark.timeZone?.identifier
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
