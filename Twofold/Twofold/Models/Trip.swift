//
//  Trip.swift
//  Twofold
//

import Foundation

/// Why this trip happened — restores the three-way distinction the app used to collapse into a
/// single `isReunionTrip` boolean. `.reunion` is specifically the trip that closes the distance
/// between the couple (crossing to see each other); a trip taken together *after* that — while
/// already in the same place, whether that's because they share a home city or because a
/// `.reunion` trip already closed the gap — is `.together`, not a second reunion. `.solo` is an
/// individual trip unrelated to the relationship. Raw values match the `trips.category` Postgres
/// enum exactly (`seeing_each_other` / `together` / `personal`).
enum TripCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case reunion = "seeing_each_other"
    case together = "together"
    case solo = "personal"

    var id: String { rawValue }

    /// Trip badges, the Add/Edit Trip category picker.
    var displayName: String {
        switch self {
        case .reunion: "Reunion"
        case .together: "Together"
        case .solo: "Solo"
        }
    }

    /// The `trip_category` PostHog property this app has always sent — kept distinct from
    /// `rawValue` (the DB's own column values) and `displayName` (UI label) so existing funnels
    /// keyed on "reunion"/"personal" keep working; "together" is a genuinely new value.
    var analyticsValue: String {
        switch self {
        case .reunion: "reunion"
        case .together: "together"
        case .solo: "personal"
        }
    }
}

/// `Codable` for `OfflineDataCache` — see `Flight`'s matching note. Nested `flights` come
/// along for free once `Flight` conforms.
struct Trip: Identifiable, Hashable, Codable {
    let id: UUID
    /// 0, 1, or 2 of the couple's members — mirrors `Flight.travelerIDs`. Almost always 1, but
    /// both partners travelling together (e.g. a joint trip back home) is a real case the old
    /// scalar `travelerID` couldn't represent at all.
    var travelerIDs: [Person.ID]
    var origin: Place
    var destination: Place
    var departureDate: Date
    var arrivalDate: Date
    var category: TripCategory
    /// Direct great-circle distance between `origin`/`destination` — the trip's *stated*
    /// endpoints, not necessarily the real distance actually flown. See `effectiveDistanceKm`.
    var distanceKm: Double
    /// Zero or more tracked flights making up this trip's real itinerary — usually one, but a
    /// connecting journey (e.g. Melbourne → Singapore → London) is genuinely two-or-more separate
    /// tracked flights sharing this trip's `id` as their `tripID`. Order isn't guaranteed; use
    /// `orderedFlights` wherever leg sequence matters.
    var flights: [Flight] = []
    var notes: String?

    init(
        id: UUID = UUID(),
        travelerIDs: [Person.ID],
        origin: Place,
        destination: Place,
        departureDate: Date,
        arrivalDate: Date,
        category: TripCategory,
        distanceKm: Double,
        flights: [Flight] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.travelerIDs = travelerIDs
        self.origin = origin
        self.destination = destination
        self.departureDate = departureDate
        self.arrivalDate = arrivalDate
        self.category = category
        self.distanceKm = distanceKm
        self.flights = flights
        self.notes = notes
    }

    var isUpcoming: Bool {
        departureDate > .now
    }

    var isActive: Bool {
        flights.contains { $0.isCurrentlyRelevant }
    }

    /// Legs in departure order — every screen that shows "the" flight for a trip (Home's active-
    /// flight card, the trip row's status badge) wants whichever leg is most relevant right now:
    /// the currently in-progress one if there is one, else the soonest upcoming one, else the
    /// most recently completed one. `flights` itself is deliberately left unordered/as-fetched.
    var orderedFlights: [Flight] {
        flights.sorted { ($0.bestDeparture ?? .distantFuture) < ($1.bestDeparture ?? .distantFuture) }
    }

    /// The one leg worth surfacing when a screen only has room for a single flight glance —
    /// an in-progress leg takes priority over a merely-scheduled one.
    var mostRelevantFlight: Flight? {
        orderedFlights.first { $0.isCurrentlyRelevant } ?? orderedFlights.first
    }

    /// The real distance actually traveled — the greater of the trip's own direct origin→
    /// destination distance and the sum of each attached leg's own distance. A trip's stated
    /// origin/destination captures the *overall* journey (e.g. Melbourne → London), but a real
    /// itinerary often routes through one or more layovers (Melbourne → Singapore → London) that
    /// cover meaningfully more ground than the direct distance between the two endpoints. Legs
    /// missing coordinate data on either end simply don't contribute (rather than blocking the
    /// whole calculation) — `distanceKm` still provides a floor via the `max`.
    var effectiveDistanceKm: Double {
        let legsDistanceKm = flights.reduce(0.0) { sum, flight in
            guard let origin = flight.origin.coordinate, let destination = flight.destination.coordinate else { return sum }
            return sum + Geo.distanceKm(origin, destination)
        }
        return max(distanceKm, legsDistanceKm)
    }

    /// The two ends of the trip, labelled the same way as each other — both airport codes, or both
    /// city names, never one of each.
    ///
    /// Deciding per side (`iataCode ?? displayCity`, independently) produced "LHR → Melbourne",
    /// which reads as a mistake rather than an abbreviation. It happens easily: a `Place` that came
    /// from a flight lookup carries an `iataCode`, while one that came from the on-device geocoder
    /// or the city search doesn't, so any trip mixing the two sources mixed the two formats. Codes
    /// are still preferred when both ends have one, since this is used on a narrow card where
    /// "LHR → MEL" fits and two full city names may not.
    var routeEndpoints: (origin: String, destination: String) {
        if let originCode = origin.iataCode, let destinationCode = destination.iataCode {
            return (originCode, destinationCode)
        }
        return (origin.displayCity, destination.displayCity)
    }
}
