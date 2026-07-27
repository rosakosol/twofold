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
    /// originally routed to the globe) which rendered a completely blank card, no pins or route at
    /// all. Both cities sit at moderate-to-high latitude on nearly opposite sides of the planet by
    /// longitude (178.4°), so their shortest path bows up almost over the pole — short in real km,
    /// but needing to span nearly the full globe left-to-right to show both endpoints.
    ///
    /// Delegates the actual "does it fit" question to `DistanceGlobeView.fitsOnGlobe` itself rather
    /// than an independent approximation of the same boundary — three earlier attempts at a cheap
    /// standalone heuristic (pure longitude separation alone, then longitude+latitude summed, then
    /// `requiredSpanDegrees` alone without also checking pole proximity) each caught some but not
    /// all of the pairs that actually break the globe: Bogotá↔Vienna (a genuinely diagonal case, not
    /// extreme on either single axis), Helsinki↔Montreal (high-latitude center silently breaking
    /// `MKCoordinateRegion` once span pushes it near a pole), and Saint Petersburg↔Riyadh /
    /// Barcelona↔Longyearbyen (well under the span cap by itself, but still pole-broken combined
    /// with their own center latitude) all slipped through one version or another. Calling the real
    /// formula means routing can never disagree with what `DistanceGlobeView` can actually render,
    /// by construction.
    private static func isFlat(distanceKm: Double, myCoordinate: CLLocationCoordinate2D, partnerCoordinate: CLLocationCoordinate2D) -> Bool {
        distanceKm > flatMapThresholdKm
            || !DistanceGlobeView.fitsOnGlobe(from: myCoordinate, to: partnerCoordinate)
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
