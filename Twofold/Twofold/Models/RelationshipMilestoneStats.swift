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
    /// Nil when the couple has not given an anniversary: there is nothing to count from, and
    /// counting from today said "0 days" to a couple of years.
    let daysTogether: Int?
    /// Broken-down calendar components of the same span `daysTogether` measures — used for the
    /// card's headline ("2 years, 3 months"), computed via `Calendar` rather than dividing the
    /// raw day count so month length varies correctly (not every "month" is 30 days). Nil with it.
    let yearsTogether: Int?
    let monthsTogether: Int?
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
    /// The longest stretch apart so far, in calendar days — see `longestSeparationDays(reunions:couple:now:)`.
    /// Nil when there is nothing to measure.
    let longestSeparationDays: Int?
    let nextReunion: Trip?
    let nextReunionDaysToGo: Int?

    init(couple: Couple, trips: [Trip], memories: [Memory]) {
        let startedDatingOn = couple.startedDatingOn
        if let startedDatingOn {
            daysTogether = max(0, TimeMath.daysSince(startedDatingOn))
            // Start-of-day on both sides, for the same reason as `daysSince` above. On the morning
            // of a sixth anniversary, against a `startedDatingOn` carrying an inherited evening
            // time-of-day, the raw instants are eleven months and thirty-one-and-a-bit days apart —
            // so the card read "5 years, 11 months" on the one day of the year it most needed to say
            // six. The time-of-day is picker residue, not something the couple chose.
            let calendar = Calendar.current
            let ymd = calendar.dateComponents(
                [.year, .month],
                from: calendar.startOfDay(for: startedDatingOn),
                to: calendar.startOfDay(for: .now)
            )
            yearsTogether = max(0, ymd.year ?? 0)
            monthsTogether = max(0, ymd.month ?? 0)
        } else {
            daysTogether = nil
            yearsTogether = nil
            monthsTogether = nil
        }
        tripCount = trips.count
        memoryCount = memories.count

        let reunions = trips.filter { $0.category == .reunion }
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

        longestSeparationDays = Self.longestSeparationDays(reunions: reunions, couple: couple)

        let upcomingReunions = reunions.filter { $0.departureDate > .now }.sorted { $0.departureDate < $1.departureDate }
        nextReunion = upcomingReunions.first
        nextReunionDaysToGo = nextReunion.map { max(0, TimeMath.daysUntil($0.departureDate)) }
    }

    /// The longest stretch apart that has already happened, in calendar days.
    ///
    /// Only reunions that have started count — a trip booked for next spring is a plan, and
    /// measuring up to it counted days nobody had lived yet. Within those:
    ///
    /// - each gap from a return to the next departure, measured from the *latest* return so far, so
    ///   a short trip inside a longer one doesn't open a gap that was never there;
    /// - the stretch since the last return — the one a couple is in the middle of, which is often
    ///   the longest — or nothing while a reunion is under way;
    /// - for a long-distance couple (both home cities known, and different), the stretch from
    ///   connecting (`connectedAt`, or `startedDatingOn`) to the first reunion, or to now if there
    ///   hasn't been one.
    ///
    /// A couple who share a home city get only the gaps between reunions. Those happened, whatever
    /// the couple's arrangement then, but the stretch since the last one is not time apart for two
    /// people who now live in the same city — counting it would grow a "longest gap" every day
    /// they spend together. Same for the time before the first reunion. With no home cities known
    /// at all, the stretch since the last reunion still counts: logging reunions is itself the sign
    /// of a couple who live apart.
    static func longestSeparationDays(reunions: [Trip], couple: Couple, now: Date = .now) -> Int? {
        let sameCity = couple.sharesHomeCity
        let longDistance = !sameCity && couple.partnerA.homeCity != nil && couple.partnerB.homeCity != nil
        let connectedAt = longDistance ? (couple.connectedAt ?? couple.startedDatingOn) : nil

        let past = reunions
            .filter { $0.departureDate <= now }
            .sorted { $0.departureDate < $1.departureDate }
        var gaps: [Int] = []
        func gap(from start: Date, to end: Date) {
            gaps.append(max(0, TimeMath.calendarDaysBetween(start, end)))
        }

        guard let first = past.first else {
            if let connectedAt { gap(from: connectedAt, to: now) }
            return gaps.max()
        }
        if let connectedAt, connectedAt < first.departureDate {
            gap(from: connectedAt, to: first.departureDate)
        }
        // `max` with the departure too, against any legacy row whose arrival isn't after it.
        var latestReturn = max(first.arrivalDate, first.departureDate)
        for reunion in past.dropFirst() {
            if reunion.departureDate > latestReturn {
                gap(from: latestReturn, to: reunion.departureDate)
            }
            latestReturn = max(latestReturn, reunion.arrivalDate)
        }
        if latestReturn > now {
            gaps.append(0)
        } else if !sameCity {
            gap(from: latestReturn, to: now)
        }
        return gaps.max()
    }

    /// "2 years, 3 months" / "1 year" / "5 months" / "23 days" — whichever of years/months are
    /// actually non-zero, dropping down to a plain day count once a couple is under a month in
    /// (where "0 years, 0 months" would otherwise read as broken rather than just new). Nil with no
    /// anniversary to measure from.
    var timeTogetherLabel: String? {
        guard let daysTogether, let yearsTogether, let monthsTogether else { return nil }
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
