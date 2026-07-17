//
//  Geo.swift
//  Twofold
//

import CoreLocation

enum Geo {
    static let earthCircumferenceKm = 40_075.0
    /// Average Earth–Moon distance, for the "x to the Moon" stat.
    static let moonDistanceKm = 384_400.0
    /// The Sun's circumference, for the "x around the Sun" stat.
    static let sunCircumferenceKm = 4_379_000.0

    static func distanceKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let location2 = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return location1.distance(from: location2) / 1000
    }

    static func percentOfEarthCircumference(_ km: Double) -> Double {
        (km / earthCircumferenceKm) * 100
    }

    struct DistanceComparison {
        let percent: Double
        /// Reads as "\(percent)% \(phrase)", e.g. "31.8% of the way around the Earth".
        let phrase: String
        let emoji: String
    }

    /// Picks whichever of Earth/Moon/Sun yields the largest (most legible) percentage — for any
    /// real couple's distance, Earth circumference wins by a wide margin (a Moon or Sun
    /// comparison would round to a fraction of a percent), so this mostly just keeps the stat
    /// honest without hand-picking Earth by name; it only stops being Earth for distances no
    /// real pair of cities on Earth could actually produce.
    static func bestDistanceComparison(km: Double) -> DistanceComparison {
        let candidates = [
            DistanceComparison(percent: km / earthCircumferenceKm * 100, phrase: "of the way around the Earth", emoji: "🌍"),
            DistanceComparison(percent: km / moonDistanceKm * 100, phrase: "of the way to the Moon", emoji: "🌙"),
            DistanceComparison(percent: km / sunCircumferenceKm * 100, phrase: "of the way around the Sun", emoji: "☀️"),
        ]
        return candidates.max { $0.percent < $1.percent }!
    }

    /// The point on the sphere equidistant from both coordinates — not a naive average of
    /// latitude/longitude, which breaks across the antimeridian (e.g. averaging 170°E and
    /// -170°W lands near 0°, the opposite side of the world from both) and isn't actually
    /// equidistant on a sphere even without wraparound.
    static func sphericalMidpoint(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let lat1 = a.latitude * .pi / 180, lon1 = a.longitude * .pi / 180
        let lat2 = b.latitude * .pi / 180, lon2 = b.longitude * .pi / 180

        let x = (cos(lat1) * cos(lon1) + cos(lat2) * cos(lon2)) / 2
        let y = (cos(lat1) * sin(lon1) + cos(lat2) * sin(lon2)) / 2
        let z = (sin(lat1) + sin(lat2)) / 2

        let longitude = atan2(y, x)
        let latitude = atan2(z, sqrt(x * x + y * y))

        return CLLocationCoordinate2D(latitude: latitude * 180 / .pi, longitude: longitude * 180 / .pi)
    }

    /// Spherical interpolation (slerp) between two coordinates along the great-circle arc that
    /// connects them — used to draw a real geodesic curve (rather than a straight chord) when
    /// projecting the route onto a flat map image.
    static func intermediateGreatCirclePoint(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, fraction f: Double) -> CLLocationCoordinate2D {
        let φ1 = a.latitude * .pi / 180, λ1 = a.longitude * .pi / 180
        let φ2 = b.latitude * .pi / 180, λ2 = b.longitude * .pi / 180

        let sinΔφ = sin((φ2 - φ1) / 2)
        let sinΔλ = sin((λ2 - λ1) / 2)
        let h = sinΔφ * sinΔφ + cos(φ1) * cos(φ2) * sinΔλ * sinΔλ
        let δ = 2 * asin(min(1, sqrt(h)))
        guard δ > 0.0000001 else { return a }

        let A = sin((1 - f) * δ) / sin(δ)
        let B = sin(f * δ) / sin(δ)
        let x = A * cos(φ1) * cos(λ1) + B * cos(φ2) * cos(λ2)
        let y = A * cos(φ1) * sin(λ1) + B * cos(φ2) * sin(λ2)
        let z = A * sin(φ1) + B * sin(φ2)
        let φi = atan2(z, sqrt(x * x + y * y))
        let λi = atan2(y, x)
        return CLLocationCoordinate2D(latitude: φi * 180 / .pi, longitude: λi * 180 / .pi)
    }

    /// The closest entry in `majorCities` to `coordinate`, provided it's actually close — a
    /// simple linear scan (a few hundred `distanceKm` calls, trivially cheap) rather than
    /// anything spatially indexed, since the list is small and this only runs on user-facing
    /// display, not in a hot loop.
    static func nearestMajorCity(to coordinate: CLLocationCoordinate2D, maxDistanceKm: Double = 90) -> MajorCity? {
        var best: (city: MajorCity, distanceKm: Double)?
        for city in majorCities {
            let distance = distanceKm(coordinate, city.coordinate)
            if best == nil || distance < best!.distanceKm {
                best = (city, distance)
            }
        }
        guard let best, best.distanceKm <= maxDistanceKm else { return nil }
        return best.city
    }
}
