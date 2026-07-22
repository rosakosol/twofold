//
//  Trip.swift
//  Twofold
//

import Foundation

struct Trip: Identifiable, Hashable {
    let id: UUID
    /// 0, 1, or 2 of the couple's members — mirrors `Flight.travelerIDs`. Almost always 1, but
    /// both partners travelling together (e.g. a joint trip back home) is a real case the old
    /// scalar `travelerID` couldn't represent at all.
    var travelerIDs: [Person.ID]
    var origin: Place
    var destination: Place
    var departureDate: Date
    var arrivalDate: Date
    /// Replaces the old three-way "reason for travel" (Reunion/Together/Personal) category —
    /// simplified to the one distinction that actually mattered for how a trip reads elsewhere
    /// in the app (the reunion card, trip badges): is this trip about seeing your partner, or
    /// not.
    var isReunionTrip: Bool
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
        isReunionTrip: Bool,
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
        self.isReunionTrip = isReunionTrip
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
}
