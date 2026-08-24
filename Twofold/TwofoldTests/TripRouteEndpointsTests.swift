//
//  TripRouteEndpointsTests.swift
//  TwofoldTests
//
//  A trip's two endpoints have to be labelled the same way as each other. Labelling them
//  independently produced "LHR → Melbourne" on the Home reunion card — an airport code on one side
//  and a city on the other, which reads as a bug rather than an abbreviation.
//

import Testing
import Foundation
@testable import Twofold

struct TripRouteEndpointsTests {

    /// Coordinates matter: `Place.displayCity` resolves through `Geo.nearestMajorCity`, so these
    /// use the real ones for the cities they name.
    private func place(city: String, country: String, iata: String?, lat: Double, lon: Double) -> Place {
        Place(city: city, country: country, iataCode: iata, latitude: lat, longitude: lon)
    }

    private func london(iata: String?) -> Place {
        place(city: "London", country: "United Kingdom", iata: iata, lat: 51.5072, lon: -0.1276)
    }

    private func melbourne(iata: String?) -> Place {
        place(city: "Melbourne", country: "Australia", iata: iata, lat: -37.8136, lon: 144.9631)
    }

    private func trip(origin: Place, destination: Place) -> Trip {
        Trip(
            travelerIDs: [], origin: origin, destination: destination,
            departureDate: .now, arrivalDate: .now, category: .reunion, distanceKm: 16_891
        )
    }

    /// The reported bug, exactly: origin came from a flight lookup (so it has a code), destination
    /// from the on-device geocoder (so it doesn't).
    @Test func oneSidedAirportCodeFallsBackToCityNamesForBothEnds() {
        let route = trip(origin: london(iata: "LHR"), destination: melbourne(iata: nil)).routeEndpoints
        #expect(route.origin == "London")
        #expect(route.destination == "Melbourne")
    }

    /// And the mirror image — a missing code on the *origin* must not leave a code on the
    /// destination either.
    @Test func missingOriginCodeAlsoDropsTheDestinationCode() {
        let route = trip(origin: london(iata: nil), destination: melbourne(iata: "MEL")).routeEndpoints
        #expect(route.origin == "London")
        #expect(route.destination == "Melbourne")
    }

    /// Codes are still preferred when both ends have one — this is a narrow card, and "LHR → MEL"
    /// fits where two full city names may not.
    @Test func bothAirportCodesArePreferredWhenAvailable() {
        let route = trip(origin: london(iata: "LHR"), destination: melbourne(iata: "MEL")).routeEndpoints
        #expect(route.origin == "LHR")
        #expect(route.destination == "MEL")
    }

    @Test func neitherSideHavingACodeUsesCityNames() {
        let route = trip(origin: london(iata: nil), destination: melbourne(iata: nil)).routeEndpoints
        #expect(route.origin == "London")
        #expect(route.destination == "Melbourne")
    }

    /// Whatever the pair resolves to, the two sides always come from the same vocabulary — that's
    /// the property the card actually depends on, independent of which branch was taken.
    @Test func endpointsNeverMixCodesAndCityNames() {
        let cases = [
            trip(origin: london(iata: "LHR"), destination: melbourne(iata: "MEL")),
            trip(origin: london(iata: "LHR"), destination: melbourne(iata: nil)),
            trip(origin: london(iata: nil), destination: melbourne(iata: "MEL")),
            trip(origin: london(iata: nil), destination: melbourne(iata: nil)),
        ]
        for trip in cases {
            let route = trip.routeEndpoints
            let originIsCode = route.origin == trip.origin.iataCode
            let destinationIsCode = route.destination == trip.destination.iataCode
            #expect(originIsCode == destinationIsCode, "mixed formats: \(route.origin) -> \(route.destination)")
        }
    }
}
