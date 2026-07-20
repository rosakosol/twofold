//
//  RelationshipMilestoneStats.swift
//  Twofold
//
//  Broader "relationship" stats — days together, trips, memories, reunions — as opposed to
//  `FlightStats`, which is specifically about flights (routes, airlines, airports). Computed
//  fresh from real trips/memories, same as `FlightStats`, never fabricated.
//

import Foundation

struct RelationshipMilestoneStats {
    let daysTogether: Int
    /// Broken-down calendar components of the same span `daysTogether` measures — used for the
    /// card's headline ("2 years, 3 months"), computed via `Calendar` rather than dividing the
    /// raw day count so month length varies correctly (not every "month" is 30 days).
    let yearsTogether: Int
    let monthsTogether: Int
    let tripCount: Int
    let memoryCount: Int
    let reunionCount: Int
    /// Total distance covered specifically by trips taken to see each other — a subset of
    /// `FlightStats.totalDistanceKm`, which counts every trip regardless of reason.
    let reunionDistanceKm: Double
    let longestTrip: Trip?
    let shortestTrip: Trip?
    /// Longest gap between one reunion trip's return and the next one's departure — nil until
    /// there have been at least two reunion trips to measure a gap between.
    let longestSeparationDays: Int?
    let nextReunion: Trip?
    let nextReunionDaysToGo: Int?

    init(trips: [Trip], memories: [Memory], startedDatingOn: Date) {
        daysTogether = max(0, Calendar.current.dateComponents([.day], from: startedDatingOn, to: .now).day ?? 0)
        let ymd = Calendar.current.dateComponents([.year, .month], from: startedDatingOn, to: .now)
        yearsTogether = max(0, ymd.year ?? 0)
        monthsTogether = max(0, ymd.month ?? 0)
        tripCount = trips.count
        memoryCount = memories.count

        let reunions = trips.filter { $0.isReunionTrip }
        reunionCount = reunions.count
        reunionDistanceKm = reunions.reduce(0) { $0 + $1.distanceKm }

        // Guards against any legacy row where arrival <= departure (bad data), rather than
        // letting a zero/negative "duration" win a max()/min() it has no business winning.
        let withDuration = trips.filter { $0.arrivalDate > $0.departureDate }
        longestTrip = withDuration.max { $0.arrivalDate.timeIntervalSince($0.departureDate) < $1.arrivalDate.timeIntervalSince($1.departureDate) }
        shortestTrip = withDuration.min { $0.arrivalDate.timeIntervalSince($0.departureDate) < $1.arrivalDate.timeIntervalSince($1.departureDate) }

        let sortedReunions = reunions.sorted { $0.departureDate < $1.departureDate }
        var longestGapDays: Int?
        if sortedReunions.count > 1 {
            for i in 1..<sortedReunions.count {
                let gapDays = Calendar.current.dateComponents([.day], from: sortedReunions[i - 1].arrivalDate, to: sortedReunions[i].departureDate).day ?? 0
                if gapDays > 0, gapDays > (longestGapDays ?? 0) {
                    longestGapDays = gapDays
                }
            }
        }
        longestSeparationDays = longestGapDays

        let upcomingReunions = reunions.filter { $0.departureDate > .now }.sorted { $0.departureDate < $1.departureDate }
        nextReunion = upcomingReunions.first
        nextReunionDaysToGo = nextReunion.map { max(0, Calendar.current.dateComponents([.day], from: .now, to: $0.departureDate).day ?? 0) }
    }

    /// "2 years, 3 months" / "1 year" / "5 months" / "23 days" — whichever of years/months are
    /// actually non-zero, dropping down to a plain day count once a couple is under a month in
    /// (where "0 years, 0 months" would otherwise read as broken rather than just new).
    var timeTogetherLabel: String {
        guard yearsTogether > 0 || monthsTogether > 0 else {
            return daysTogether == 1 ? "1 day" : "\(daysTogether) days"
        }
        var parts: [String] = []
        if yearsTogether > 0 { parts.append(yearsTogether == 1 ? "1 year" : "\(yearsTogether) years") }
        if monthsTogether > 0 { parts.append(monthsTogether == 1 ? "1 month" : "\(monthsTogether) months") }
        return parts.joined(separator: ", ")
    }

    /// Trips run days-to-weeks, not hours-to-minutes like `FlightStats.duration` — a day-count
    /// reads far more naturally than "336h 0m" would.
    static func tripDuration(_ trip: Trip) -> String {
        let days = max(1, Calendar.current.dateComponents([.day], from: trip.departureDate, to: trip.arrivalDate).day ?? 1)
        return days == 1 ? "1 day" : "\(days) days"
    }
}
