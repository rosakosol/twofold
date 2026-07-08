//
//  Geo.swift
//  Twofold
//

import CoreLocation

enum Geo {
    static let earthCircumferenceKm = 40_075.0

    static func distanceKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let location2 = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return location1.distance(from: location2) / 1000
    }

    static func percentOfEarthCircumference(_ km: Double) -> Double {
        (km / earthCircumferenceKm) * 100
    }
}
