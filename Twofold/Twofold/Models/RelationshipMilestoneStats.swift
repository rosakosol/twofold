//
//  RelationshipMilestoneStats.swift
//  Twofold
//
//  Broader "relationship" stats — days together, trips, memories, reunions — as opposed to
//  `FlightStats`, which is specifically about flights (routes, airlines, airports). Computed
//  fresh from real trips/memories, same as `FlightStats`, never fabricated.
//

import CoreLocation
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
    /// The greatest distance ever recorded between this couple's two home cities — the max of
    /// the persisted historical high-water-mark (`couple.maxDistanceKm`, updated opportunistically
    /// by `AppModel.noteCurrentDistanceIfRecord`) and whatever their current home cities compute
    /// to right now, so this never shows a stale, too-low number in the gap before the next
    /// persisted update lands. Was `reunionDistanceKm` (the *sum* of reunion-trip distances flown
    /// — a fundamentally different, historical-total metric) before this was rebuilt around a
    /// live "how far apart have you two been" milestone instead.
    let longestDistanceKm: Double
    let longestTrip: Trip?
    let shortestTrip: Trip?
    /// Longest gap between one reunion trip's return and the next one's departure. Falls back to
    /// "how long since you've been apart" — measured from `couple.connectedAt` (or
    /// `startedDatingOn` if that's somehow unset) — when there aren't two reunion trips to measure
    /// a historical gap between but the couple is currently in different home cities, so a couple
    /// with no trips yet sees a real running count instead of a blank "—".
    let longestSeparationDays: Int?
    let nextReunion: Trip?
    let nextReunionDaysToGo: Int?

    init(couple: Couple, trips: [Trip], memories: [Memory]) {
        let startedDatingOn = couple.startedDatingOn
        daysTogether = max(0, Calendar.current.dateComponents([.day], from: startedDatingOn, to: .now).day ?? 0)
        let ymd = Calendar.current.dateComponents([.year, .month], from: startedDatingOn, to: .now)
        yearsTogether = max(0, ymd.year ?? 0)
        monthsTogether = max(0, ymd.month ?? 0)
        tripCount = trips.count
        memoryCount = memories.count

        let reunions = trips.filter { $0.isReunionTrip }
        reunionCount = reunions.count

        var currentDistanceKm: Double?
        if let mine = couple.partnerA.homeCity?.coordinate, let theirs = couple.partnerB.homeCity?.coordinate {
            currentDistanceKm = Geo.distanceKm(mine, theirs)
        }
        longestDistanceKm = max(couple.maxDistanceKm ?? 0, currentDistanceKm ?? 0)

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
        if let longestGapDays {
            longestSeparationDays = longestGapDays
        } else if !couple.sharesHomeCity, couple.partnerA.homeCity != nil, couple.partnerB.homeCity != nil {
            let since = couple.connectedAt ?? startedDatingOn
            longestSeparationDays = max(0, Calendar.current.dateComponents([.day], from: since, to: .now).day ?? 0)
        } else {
            longestSeparationDays = nil
        }

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
