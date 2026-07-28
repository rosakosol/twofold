//
//  RouteMapShareCardTests.swift
//  TwofoldTests
//
//  Regression coverage for RouteMapShareCard.region(for:_:) — confirmed live crash: a naive
//  abs(longitude difference) breaks across the antimeridian (same bug class Geo.sphericalMidpoint's
//  own doc comment warns against for the region *center*), producing a span MKMapSnapshotOptions
//  rejects with an uncaught NSInvalidArgumentException that aborts the whole process. Reproduced
//  via the Share sheet's Route Map page on a real SFO -> Taipei flight (CI5175).
//

import CoreLocation
import MapKit
import Testing
@testable import Twofold

struct RouteMapShareCardTests {

    private let sfo = CLLocationCoordinate2D(latitude: 37.6213, longitude: -122.3790)
    private let taipei = CLLocationCoordinate2D(latitude: 25.0777, longitude: 121.2322)
    private let melbourne = CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631)
    private let losAngeles = CLLocationCoordinate2D(latitude: 33.9416, longitude: -118.4085)

    /// The exact crash: a raw longitude difference of ~243.6° (×1.7 ≈ 414°) blew well past what
    /// `MKMapSnapshotOptions.setRegion:` accepts.
    @Test func regionAcrossAntimeridianStaysWithinValidSpan() {
        let region = RouteMapShareCard.region(for: sfo, taipei)
        #expect(region.span.longitudeDelta <= 170)
        #expect(region.span.longitudeDelta.isFinite)
        #expect(region.span.latitudeDelta <= 170)
    }

    /// A second antimeridian-crossing pair (Melbourne -> Los Angeles, ~263° raw diff) to make sure
    /// the fix isn't accidentally specific to the SFO/Taipei coordinates.
    @Test func regionAcrossAntimeridianStaysWithinValidSpanForSecondRoute() {
        let region = RouteMapShareCard.region(for: melbourne, losAngeles)
        #expect(region.span.longitudeDelta <= 170)
        #expect(region.span.latitudeDelta <= 170)
    }

    /// An ordinary short-haul domestic route (well under the antimeridian) should be unaffected by
    /// the wraparound fix — still floors at the existing 10° minimum zoom.
    @Test func regionForOrdinaryRouteKeepsSensibleFloor() {
        let melbourneAirport = CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631)
        let sydney = CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)
        let region = RouteMapShareCard.region(for: melbourneAirport, sydney)
        #expect(region.span.latitudeDelta >= 10)
        #expect(region.span.longitudeDelta >= 10)
        #expect(region.span.longitudeDelta < 30)
    }
}
