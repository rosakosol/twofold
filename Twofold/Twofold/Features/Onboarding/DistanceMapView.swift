//
//  DistanceMapView.swift
//  Twofold
//
//  Picks between `DistanceGlobeView` (both pins share one globe crop) and `DistanceFlatMapView`
//  (too far apart for that — see `flatMapThresholdKm`'s own comment) based on real distance, and
//  fetches whichever snapshot type that pick needs. Used identically by both `PersonalizedInsightView`
//  (live) and `DistanceSnapshotCard` (share) — that's what keeps them looking like the same moment.
//

import SwiftUI
import MapKit

struct DistanceMapView: View {
    let myCity: Place
    let partnerCity: Place
    let distanceKm: Double
    let selfPhoto: UIImage?
    let partnerPhoto: UIImage?
    let mapSnapshot: MKMapSnapshotter.Snapshot?

    /// Chosen empirically (see `DistanceGlobeView`'s own doc comment): the globe held up fine
    /// through ~11,000km, was visibly cramping a pin/label together by 12,000-13,000km, and could
    /// never fit both pins at all much past 15,000km regardless of how the crop was shifted or
    /// widened. This sits just under where the cramping starts, rather than at the higher distance
    /// where it becomes outright broken.
    static let flatMapThresholdKm: Double = 12_000

    /// Great-circle *distance* alone isn't a reliable proxy for "small enough to crop onto one
    /// globe" — found via testing Vancouver↔Dubai (11,731km, under `flatMapThresholdKm`, so
    /// routed to the globe) which rendered a completely blank card, no pins or route at all. Both
    /// cities sit at moderate-to-high latitude on nearly opposite sides of the planet by
    /// longitude (178.4°), so their shortest path bows up almost over the pole — short in real
    /// km, but needing to span nearly the full globe left-to-right to show both endpoints, far
    /// past what `DistanceGlobeView`'s own 120°-capped span (tuned for pairs that actually need
    /// only that much) can hold. `DistanceFlatMapView` already has the retry-with-growing-span
    /// logic (up to 178°) and a graceful self-centered fallback for pairs that still don't fit —
    /// exactly what a wide-longitude pair like this needs, regardless of how short the real
    /// distance between them is.
    private static func longitudeSeparationDegrees(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        var delta = b.longitude - a.longitude
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return abs(delta)
    }

    private static func isFlat(distanceKm: Double, myCoordinate: CLLocationCoordinate2D, partnerCoordinate: CLLocationCoordinate2D) -> Bool {
        distanceKm > flatMapThresholdKm || longitudeSeparationDegrees(myCoordinate, partnerCoordinate) > 100
    }

    private var isFlat: Bool { Self.isFlat(distanceKm: distanceKm, myCoordinate: myCity.coordinate, partnerCoordinate: partnerCity.coordinate) }

    var body: some View {
        if isFlat {
            DistanceFlatMapView(myCity: myCity, partnerCity: partnerCity, selfPhoto: selfPhoto, partnerPhoto: partnerPhoto, mapSnapshot: mapSnapshot)
        } else {
            DistanceGlobeView(myCity: myCity, partnerCity: partnerCity, selfPhoto: selfPhoto, partnerPhoto: partnerPhoto, mapSnapshot: mapSnapshot)
        }
    }

    static func loadMapSnapshot(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, distanceKm: Double) async -> MKMapSnapshotter.Snapshot? {
        if isFlat(distanceKm: distanceKm, myCoordinate: a, partnerCoordinate: b) {
            return await DistanceFlatMapView.loadMapSnapshot(from: a, to: b)
        } else {
            return await DistanceGlobeView.loadMapSnapshot(from: a, to: b)
        }
    }
}

#Preview("Globe") {
    DistanceMapView(
        myCity: Place.commonCities.first { $0.city == "Melbourne" }!,
        partnerCity: Place.commonCities.first { $0.city == "Singapore" }!,
        distanceKm: 6_054,
        selfPhoto: nil,
        partnerPhoto: nil,
        mapSnapshot: nil
    )
    .padding()
    .background(Color.black)
}

#Preview("Flat") {
    DistanceMapView(
        myCity: Place.commonCities.first { $0.city == "Melbourne" }!,
        partnerCity: Place.commonCities.first { $0.city == "New York" }!,
        distanceKm: 16_672,
        selfPhoto: nil,
        partnerPhoto: nil,
        mapSnapshot: nil
    )
    .padding()
    .background(Color.black)
}
