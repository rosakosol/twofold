//
//  Place.swift
//  Twofold
//

import CoreLocation

struct Place: Identifiable, Hashable, Codable {
    let id: UUID
    var city: String
    var country: String
    var iataCode: String?
    var latitude: Double
    var longitude: Double
    /// IANA identifier (e.g. "Australia/Melbourne"). Nil for places added later via
    /// live city search until that's resolved and backfilled.
    var timeZoneIdentifier: String?

    init(id: UUID = UUID(), city: String, country: String, iataCode: String? = nil, latitude: Double, longitude: Double, timeZoneIdentifier: String? = nil) {
        self.id = id
        self.city = city
        self.country = country
        self.iataCode = iataCode
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var timeZone: TimeZone? {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    /// Best-effort "real" city name for display — `city` itself is whatever Apple's on-device
    /// geocoder returned for this coordinate, which for many countries (Australia among them)
    /// is the *suburb*, since there's no separate "locality vs. suburb" distinction in their
    /// addressing (e.g. a West Footscray address geocodes with `locality` = "West Footscray",
    /// not "Melbourne"). Resolves to the nearest bundled major city within a reasonable radius,
    /// falling back to the raw geocoded name for anywhere too far from any of them (small towns,
    /// rural areas) rather than pointing at a "nearest major city" that isn't really local.
    var displayCity: String {
        Geo.nearestMajorCity(to: coordinate)?.name ?? city
    }

    static func == (lhs: Place, rhs: Place) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Curated pickable list reused by every city picker (onboarding home city, trip origin/destination, etc.)
    static let commonCities: [Place] = [
        Place(city: "Melbourne", country: "Australia", iataCode: "MEL", latitude: -37.8136, longitude: 144.9631, timeZoneIdentifier: "Australia/Melbourne"),
        Place(city: "Singapore", country: "Singapore", iataCode: "SIN", latitude: 1.3521, longitude: 103.8198, timeZoneIdentifier: "Asia/Singapore"),
        Place(city: "Bangkok", country: "Thailand", iataCode: "BKK", latitude: 13.7563, longitude: 100.5018, timeZoneIdentifier: "Asia/Bangkok"),
        Place(city: "Tokyo", country: "Japan", iataCode: "HND", latitude: 35.6762, longitude: 139.6503, timeZoneIdentifier: "Asia/Tokyo"),
        Place(city: "London", country: "United Kingdom", iataCode: "LHR", latitude: 51.5072, longitude: -0.1276, timeZoneIdentifier: "Europe/London"),
        Place(city: "New York", country: "United States", iataCode: "JFK", latitude: 40.7128, longitude: -74.0060, timeZoneIdentifier: "America/New_York"),
        Place(city: "Sydney", country: "Australia", iataCode: "SYD", latitude: -33.8688, longitude: 151.2093, timeZoneIdentifier: "Australia/Sydney"),
    ]
}
