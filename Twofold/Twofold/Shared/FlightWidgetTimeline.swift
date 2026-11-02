//
//  FlightWidgetTimeline.swift
//  Twofold
//
//  What the two flight widgets show at each moment of their timelines, and when they ask to be
//  reloaded. Pure functions of the snapshot and a date, out here rather than in the providers so
//  the app's tests can check every entry against the clock.
//
//  Shared with LiveActivitiesExtension (see the "Twofold" folder's membership exception for that
//  target in project.pbxproj).
//

import Foundation

nonisolated enum FlightWidgetTimeline {
    /// One timeline entry's worth of flight: which flight, and how it stands at `date`.
    struct Moment {
        var date: Date
        /// Nil when there is no flight to show.
        var flight: WidgetSnapshot.FlightInfo?
        var status: FlightStatus?
        var isDeparted: Bool
        /// Take-off before departure, touchdown after. Can be in the past.
        var target: Date?
        var delaySeconds: Int?
        var progress: Double

        /// Time left to `target`, nil once it has passed or when there is none.
        var remaining: TimeInterval? {
            guard let target, target > date else { return nil }
            return target.timeIntervalSince(date)
        }
    }

    /// The entries, and when to ask for the next timeline: nil means `.atEnd`.
    struct Plan {
        var moments: [Moment]
        var reloadAt: Date?
    }

    /// The most entries one timeline carries. WidgetKit's daily budget counts reloads, not
    /// entries, so this only bounds the work of rendering ahead.
    static let entryCap = 150

    // MARK: - Flight Tracking

    /// On the minute marks before take-off and touchdown (see `TimeMath.countdownMoments`), each
    /// entry worked out for its own moment.
    static func trackingPlan(_ snapshot: WidgetSnapshot?, from now: Date) -> Plan {
        let flight = snapshot?.nextFlight
        let targets = [flight?.bestDeparture, flight?.bestArrival].compactMap { $0 }
        let dates = Array(TimeMath.countdownMoments(to: targets, from: now).prefix(entryCap))
        // Nothing to count down to: look again in fifteen minutes.
        let reloadAt = dates.count > 1 ? dates.last! : now.addingTimeInterval(900)
        return Plan(moments: dates.map { trackingMoment(snapshot, at: $0) }, reloadAt: reloadAt)
    }

    /// The Flight Tracking widget at one moment.
    static func trackingMoment(_ snapshot: WidgetSnapshot?, at date: Date) -> Moment {
        let flight = snapshot?.nextFlight
        let isDeparted = (flight?.bestDeparture ?? .distantFuture) <= date
        return Moment(
            date: date,
            flight: flight,
            status: flight?.status.projected(departure: flight?.bestDeparture, arrival: flight?.bestArrival, now: date),
            isDeparted: isDeparted,
            target: isDeparted ? flight?.bestArrival : flight?.bestDeparture,
            delaySeconds: flight?.delaySeconds,
            progress: progress(for: flight, at: date)
        )
    }

    /// "Departs in" or "Lands in", over the time left.
    static func countdownLabel(isDeparted: Bool, target: Date?, at date: Date) -> String? {
        isDeparted ? "Lands in" : "Departs in"
    }

    /// Mirrors `Flight.progress`, evaluated at an arbitrary moment rather than "now" — same
    /// guard, so an arrival that isn't after its departure can't produce a NaN. The stored value
    /// was correct when the app last ran and has been frozen ever since.
    static func progress(for flight: WidgetSnapshot.FlightInfo?, at date: Date) -> Double {
        guard let flight else { return 0 }
        guard let departure = flight.bestDeparture, let arrival = flight.bestArrival, arrival > departure else {
            return flight.progress
        }
        return min(1, max(0, date.timeIntervalSince(departure) / arrival.timeIntervalSince(departure)))
    }

    // MARK: - Flight Countdown

    /// Which flight a Flight Countdown widget counts down to: the picked one if it's still among
    /// the couple's tracked flights, otherwise the soonest (an unconfigured widget, or one whose
    /// picked flight has since landed or been removed, shows the nearest flight).
    static func selectedFlight(_ snapshot: WidgetSnapshot?, preferring selectedID: UUID?) -> WidgetSnapshot.FlightInfo? {
        let tracked = snapshot?.trackedFlights ?? []
        if let selectedID, let match = tracked.first(where: { $0.id == selectedID }) {
            return match
        }
        return tracked.first ?? snapshot?.nextFlight
    }

    /// A tiered run of entries, dense near the target, then `.atEnd`.
    static func countdownPlan(_ snapshot: WidgetSnapshot?, preferring selectedID: UUID?, from now: Date) -> Plan {
        guard let flight = selectedFlight(snapshot, preferring: selectedID) else {
            return Plan(moments: [Moment(date: now, flight: nil, status: nil, isDeparted: false, target: nil, delaySeconds: nil, progress: 0)], reloadAt: nil)
        }
        let isDeparted = (flight.bestDeparture ?? .distantFuture) <= now
        let target = isDeparted ? flight.bestArrival : flight.bestDeparture
        let moment = { (date: Date) in
            Moment(date: date, flight: flight, status: flight.status, isDeparted: isDeparted, target: target, delaySeconds: flight.delaySeconds, progress: flight.progress)
        }
        guard let target else { return Plan(moments: [moment(now)], reloadAt: nil) }
        return Plan(moments: tieredDates(from: now, to: target).map(moment), reloadAt: nil)
    }

    /// Dense near the target, sparse further out — 60s apart inside the final 10 minutes, 5
    /// minutes apart inside the final hour, 30 minutes apart beyond that.
    private static func tieredDates(from now: Date, to target: Date, cap: Int = 200) -> [Date] {
        guard target > now else { return [now] }
        var dates: [Date] = []
        var cursor = now
        while cursor < target, dates.count < cap {
            dates.append(cursor)
            let remaining = target.timeIntervalSince(cursor)
            let step: TimeInterval = remaining <= 600 ? 60 : (remaining <= 3600 ? 300 : 1800)
            cursor = cursor.addingTimeInterval(step)
        }
        dates.append(target)
        return dates
    }
}
