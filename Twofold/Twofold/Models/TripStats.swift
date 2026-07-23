//
//  TripStats.swift
//  Twofold
//
//  The Stats tab's Trips card — everything about trips *as trips* (how many, how far, how long,
//  where), independent of both `FlightStats` (which only ever counts a trip if it has a real
//  tracked flight attached) and `RelationshipMilestoneStats` (reunions/days-together framing).
//  Computed from every trip the couple has, same as `RelationshipMilestoneStats`, never fabricated.
//

import Foundation

struct TripStats {
    struct Ranked {
        let name: String
        let count: Int
    }

    let totalTrips: Int
    /// `effectiveDistanceKm` per trip (flown-leg distance where available, falling back to the
    /// direct origin→destination distance otherwise — see `Trip.effectiveDistanceKm`), so a trip
    /// with no linked flight still contributes its real distance here, unlike `FlightStats`.
    let totalDistanceKm: Double
    let totalDays: Int
    let longestTrip: Trip?
    let shortestTrip: Trip?
    let reunionCount: Int
    let personalCount: Int
    let upcomingCount: Int
    let pastCount: Int
    /// The single most-visited destination city, by trip count — nil only when there are no
    /// trips at all.
    let topDestination: Ranked?

    init(trips: [Trip]) {
        totalTrips = trips.count
        totalDistanceKm = trips.reduce(0) { $0 + $1.effectiveDistanceKm }
        totalDays = trips.reduce(0) { sum, trip in
            sum + max(0, Calendar.current.dateComponents([.day], from: trip.departureDate, to: trip.arrivalDate).day ?? 0)
        }

        // Guards against any legacy row where arrival <= departure (bad data), rather than
        // letting a zero/negative "duration" win a max()/min() it has no business winning — same
        // guard `RelationshipMilestoneStats` uses for its own longest/shortest trip.
        let withDuration = trips.filter { $0.arrivalDate > $0.departureDate }
        longestTrip = withDuration.max { $0.arrivalDate.timeIntervalSince($0.departureDate) < $1.arrivalDate.timeIntervalSince($1.departureDate) }
        shortestTrip = withDuration.min { $0.arrivalDate.timeIntervalSince($0.departureDate) < $1.arrivalDate.timeIntervalSince($1.departureDate) }

        reunionCount = trips.count { $0.isReunionTrip }
        personalCount = totalTrips - reunionCount
        upcomingCount = trips.count { $0.isUpcoming }
        pastCount = totalTrips - upcomingCount

        var destinationCounts: [String: Int] = [:]
        for trip in trips {
            destinationCounts[trip.destination.displayCity, default: 0] += 1
        }
        topDestination = destinationCounts.max { $0.value < $1.value }.map { Ranked(name: $0.key, count: $0.value) }
    }
}
