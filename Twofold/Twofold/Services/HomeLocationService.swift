//
//  HomeLocationService.swift
//  Twofold
//
//  One-shot "use my current location" flow — requests `.whenInUse` authorization if needed,
//  takes a single location fix, then reverse-geocodes it into a `Place` (mirrors the shape
//  CitySearchCompleter.resolve(_:) already builds for text-search results). No continuous
//  tracking, no background usage — the app has no other use for location beyond this.
//

import CoreLocation
import Foundation

@Observable
@MainActor
final class HomeLocationService: NSObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case idle
        case requesting
        case resolved(Place)
        case failed(String)
        case deniedOrRestricted
    }

    private let manager = CLLocationManager()
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var state: State = .idle

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
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

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            switch manager.authorizationStatus {
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
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            do {
                let place = try await Self.resolvePlace(from: location)
                state = .resolved(place)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            state = .failed(error.localizedDescription)
        }
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
}
