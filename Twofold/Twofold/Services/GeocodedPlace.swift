//
//  GeocodedPlace.swift
//  Twofold
//
//  MapKit's geocoding (iOS 26), turned into the app's `Place`. Replaces `CLGeocoder`, which iOS 26
//  deprecated in favour of `MKGeocodingRequest` and `MKReverseGeocodingRequest`.
//
//  The requests answer with `MKMapItem`s, which can't be built with an address in a test. So the
//  few fields the app reads are copied into `GeocodedAddress` first, and every rule about which
//  field becomes which part of a `Place` lives in `GeocodedPlace`, where a test can reach it.
//
//  Field by field, against what `CLPlacemark` gave:
//    locality  -> addressRepresentations.cityName   (the city, never a suburb or a full address)
//    country   -> addressRepresentations.regionName (the country's name, "Australia")
//    name      -> MKMapItem.name                     (a dropped pin's place or street)
//    timeZone  -> MKMapItem.timeZone
//    location  -> MKMapItem.location
//

import CoreLocation
import MapKit

/// What the app reads from a geocoded map item.
struct GeocodedAddress: Equatable {
    var name: String?
    var cityName: String?
    var regionName: String?
    var coordinate: CLLocationCoordinate2D
    var timeZoneIdentifier: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.cityName == rhs.cityName && lhs.regionName == rhs.regionName
            && lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.timeZoneIdentifier == rhs.timeZoneIdentifier
    }
}

extension GeocodedAddress {
    init(_ item: MKMapItem) {
        self.init(
            name: item.name,
            cityName: item.addressRepresentations?.cityName,
            regionName: item.addressRepresentations?.regionName,
            coordinate: item.location.coordinate,
            timeZoneIdentifier: item.timeZone?.identifier
        )
    }

    /// The first map item MapKit reverse-geocodes this location to, or nil when it names nothing.
    @MainActor
    static func reverseGeocode(_ location: CLLocation) async throws -> GeocodedAddress? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        return try await request.mapItems.first.map(GeocodedAddress.init)
    }

    /// The first map item MapKit finds for an address typed as text, or nil.
    @MainActor
    static func geocode(_ address: String) async throws -> GeocodedAddress? {
        guard let request = MKGeocodingRequest(addressString: address) else { return nil }
        return try await request.mapItems.first.map(GeocodedAddress.init)
    }
}

enum GeocodedPlace {
    /// Home's "where am I": the city and country only, at a coordinate the caller has already
    /// coarsened. Nil when MapKit gives no city — the distance card wants a city or nothing.
    static func homeCity(from address: GeocodedAddress, at coordinate: CLLocationCoordinate2D) -> Place? {
        guard let city = address.cityName, !city.isEmpty else { return nil }
        return Place(
            city: city,
            country: address.regionName ?? "",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneIdentifier: address.timeZoneIdentifier
        )
    }

    /// A memory's typed address: the text itself is the label, MapKit supplies where it is.
    static func typedAddress(_ text: String, from address: GeocodedAddress) -> Place {
        Place(
            city: text,
            country: address.regionName ?? "",
            iataCode: nil,
            latitude: address.coordinate.latitude,
            longitude: address.coordinate.longitude,
            timeZoneIdentifier: address.timeZoneIdentifier
        )
    }

    /// A memory's dropped pin: the pin's own coordinate, labelled with the place or street MapKit
    /// names there, then the city, then the bare coordinate for a pin in open ocean.
    static func droppedPin(at coordinate: CLLocationCoordinate2D, from address: GeocodedAddress?) -> Place {
        let label = [address?.name, address?.cityName]
            .compactMap { $0 }
            .first { !$0.isEmpty } ?? String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
        return Place(
            city: label,
            country: address?.regionName ?? "",
            iataCode: nil,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneIdentifier: address?.timeZoneIdentifier
        )
    }
}
