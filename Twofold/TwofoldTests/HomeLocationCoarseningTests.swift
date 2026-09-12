//
//  HomeLocationCoarseningTests.swift
//  TwofoldTests
//
//  What the device's own position is allowed to become before it is written to a table the whole
//  world can read.
//
//  `public.places` is shared reference data, deduplicated on `(city, country)` and selectable by
//  every signed-in user. `HomeLocationService` used to put the raw CoreLocation fix into the
//  `Place` it built, and `BackendService.findOrCreatePlaceID` inserts that row the first time
//  anyone reaches a given city — so the first person to open the app in a town published a
//  house-level coordinate as that town's, to everyone, without being asked. The hourly refresh in
//  `RootView.refreshCurrentCityIfNeeded()` is what made it silent: it takes a fix on foreground
//  with nobody touching anything.
//
//  These pin the coarsening rather than the plumbing, because the coarsening is the part with a
//  number in it that someone could later "simplify" back to the raw fix.
//

import CoreLocation
import Testing
@testable import Twofold

struct HomeLocationCoarseningTests {

    /// A fix inside a major city resolves to that city's own centre — not near it, *it*. The
    /// returned coordinate has to be independent of where in the city the reading was taken,
    /// which is the whole point: two people on opposite sides of Melbourne write the same row.
    @Test func majorCityFixSnapsToTheCityCentre() throws {
        let city = try #require(Geo.majorCities.first { $0.name == "Melbourne" })

        // Roughly Footscray — a few km from the CBD, well inside the 90km radius.
        let fix = CLLocation(latitude: -37.7997, longitude: 144.8999)
        let result = HomeLocationService.cityLevelCoordinate(for: fix)

        #expect(result.latitude == city.latitude)
        #expect(result.longitude == city.longitude)
    }

    /// Two different addresses in the same city must be indistinguishable afterwards. If this
    /// fails, the stored row still carries something about which part of the city someone is in.
    @Test func twoAddressesInOneCityBecomeTheSameCoordinate() {
        let northOfTheCBD = CLLocation(latitude: -37.7700, longitude: 144.9700)
        let southOfTheCBD = CLLocation(latitude: -37.8800, longitude: 144.9900)

        let a = HomeLocationService.cityLevelCoordinate(for: northOfTheCBD)
        let b = HomeLocationService.cityLevelCoordinate(for: southOfTheCBD)

        #expect(a.latitude == b.latitude)
        #expect(a.longitude == b.longitude)
    }

    /// The case the bundled list doesn't cover. Nowhere near a major city, so there is no centre
    /// to snap to and the fix is rounded instead — to a ~11km grid, which is coarse enough that
    /// the row cannot point at a property.
    @Test func remoteFixIsRoundedRatherThanPublishedExactly() {
        // Deep in the Simpson Desert — the nearest bundled city is many hundreds of km away.
        let fix = CLLocation(latitude: -24.86731, longitude: 137.21449)
        let result = HomeLocationService.cityLevelCoordinate(for: fix)

        // Tolerance, not equality: both sides are computed doubles and 0.1 has no exact binary
        // representation, so `-249.0 / 10 == -24.9` is not something to rest a test on.
        #expect(abs(result.latitude - (-24.9)) < 0.000_001)
        #expect(abs(result.longitude - 137.2) < 0.000_001)
        #expect(result.latitude != fix.coordinate.latitude)
        #expect(result.longitude != fix.coordinate.longitude)
    }

    /// Rounding has to survive the equator and the prime meridian in both directions — a naive
    /// truncation loses the sign and moves someone to the other hemisphere.
    @Test func roundingHoldsAcrossBothHemispheres() {
        let southWest = HomeLocationService.cityLevelCoordinate(
            for: CLLocation(latitude: -0.06, longitude: -0.04)
        )
        #expect(abs(southWest.latitude - (-0.1)) < 0.000_001)
        #expect(abs(southWest.longitude) < 0.000_001)

        let northEast = HomeLocationService.cityLevelCoordinate(
            for: CLLocation(latitude: 0.06, longitude: 0.04)
        )
        #expect(abs(northEast.latitude - 0.1) < 0.000_001)
        #expect(abs(northEast.longitude) < 0.000_001)
    }

    /// No fix, anywhere, may come back unchanged at full precision. A single raw coordinate
    /// reaching `places` is the bug this file exists for.
    @Test(arguments: [
        (-37.81361, 144.96307),   // Melbourne CBD
        (51.50722, -0.12758),     // London
        (35.67620, 139.65031),    // Tokyo
        (-24.86731, 137.21449),   // remote
        (64.12345, -21.87654),    // Reykjavik-ish
    ])
    func noFixSurvivesAtFullPrecision(_ latitude: Double, _ longitude: Double) {
        let result = HomeLocationService.cityLevelCoordinate(
            for: CLLocation(latitude: latitude, longitude: longitude)
        )
        let unchanged = result.latitude == latitude && result.longitude == longitude
        #expect(!unchanged)
    }
}
