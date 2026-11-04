//
//  MemoriesMapLoadingTests.swift
//  TwofoldTests
//
//  The Memories map now stays under a cover until the tiles for the region it opens on, and the
//  photos of the pins in that region, have loaded — so it appears once rather than tile by tile.
//  What is pinned: that the cover gives up quickly, and which pins it waits for.
//

import MapKit
import Testing
@testable import Twofold

/// Which pins' photos the map warms before it shows: the ones in the region it opens on.
@MainActor
struct MemoriesMapRegionTests {

    @Test("the cover lifts within a few seconds, loaded or not")
    func tileTimeoutIsBounded() {
        #expect(MemoriesMapView.tileWait <= .seconds(3))
    }

    private let melbourne = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631),
        latitudinalMeters: 40_000, longitudinalMeters: 40_000
    )

    @Test("a pin in the opening region is in it, one across the world is not")
    func containsNearbyOnly() {
        #expect(MemoriesMapView.region(melbourne, contains: CLLocationCoordinate2D(latitude: -37.85, longitude: 144.98)))
        #expect(!MemoriesMapView.region(melbourne, contains: CLLocationCoordinate2D(latitude: 41.9, longitude: 12.5)))
    }

    /// A region straddling the antimeridian — Fiji — must not lose the pins on its far side.
    @Test("longitude wraps across the antimeridian")
    func wrapsAntimeridian() {
        let fiji = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -17.7, longitude: 179.9),
            span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
        )
        #expect(MemoriesMapView.region(fiji, contains: CLLocationCoordinate2D(latitude: -17.7, longitude: -179.8)))
        #expect(!MemoriesMapView.region(fiji, contains: CLLocationCoordinate2D(latitude: -17.7, longitude: 170)))
    }
}
