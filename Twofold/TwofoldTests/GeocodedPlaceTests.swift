//
//  GeocodedPlaceTests.swift
//  TwofoldTests
//
//  Which part of a MapKit geocoding answer becomes which part of a `Place`, now that `CLGeocoder`
//  and its `CLPlacemark` are gone.
//

import CoreLocation
import Testing
@testable import Twofold

@Suite("Geocoded places")
struct GeocodedPlaceTests {

    private let fitzroy = GeocodedAddress(
        name: "123 Brunswick St",
        cityName: "Melbourne",
        regionName: "Australia",
        coordinate: CLLocationCoordinate2D(latitude: -37.7983, longitude: 144.9781),
        timeZoneIdentifier: "Australia/Melbourne"
    )

    @Test("Home takes the city, never the street, at the coarsened coordinate it is given")
    func homeCity() throws {
        let centre = CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631)
        let place = try #require(GeocodedPlace.homeCity(from: fitzroy, at: centre))
        #expect(place.city == "Melbourne")
        #expect(place.country == "Australia")
        #expect(place.latitude == centre.latitude)
        #expect(place.longitude == centre.longitude)
        #expect(place.timeZoneIdentifier == "Australia/Melbourne")
    }

    @Test("Home gives up rather than guess when MapKit names no city")
    func homeWithoutCity() {
        var ocean = fitzroy
        ocean.cityName = nil
        #expect(GeocodedPlace.homeCity(from: ocean, at: ocean.coordinate) == nil)
        ocean.cityName = ""
        #expect(GeocodedPlace.homeCity(from: ocean, at: ocean.coordinate) == nil)
    }

    @Test("A typed address keeps the words typed, with MapKit's coordinate and country")
    func typedAddress() {
        let place = GeocodedPlace.typedAddress("Brunswick St, Fitzroy", from: fitzroy)
        #expect(place.city == "Brunswick St, Fitzroy")
        #expect(place.country == "Australia")
        #expect(place.latitude == fitzroy.coordinate.latitude)
        #expect(place.timeZoneIdentifier == "Australia/Melbourne")
        #expect(place.iataCode == nil)
    }

    @Test("A dropped pin reads the place's name, then the city, then the coordinate")
    func droppedPin() {
        let pin = CLLocationCoordinate2D(latitude: -37.79831, longitude: 144.97812)
        #expect(GeocodedPlace.droppedPin(at: pin, from: fitzroy).city == "123 Brunswick St")
        #expect(GeocodedPlace.droppedPin(at: pin, from: fitzroy).latitude == pin.latitude)

        var unnamed = fitzroy
        unnamed.name = nil
        #expect(GeocodedPlace.droppedPin(at: pin, from: unnamed).city == "Melbourne")

        let ocean = GeocodedPlace.droppedPin(at: CLLocationCoordinate2D(latitude: -40.5, longitude: 150.25), from: nil)
        #expect(ocean.city == "-40.5000, 150.2500")
        #expect(ocean.country == "")
        #expect(ocean.timeZoneIdentifier == nil)
    }
}
