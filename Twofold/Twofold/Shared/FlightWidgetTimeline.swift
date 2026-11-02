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

        /// What the flight came to, once there is nothing left to count: cancelled or diverted at
        /// any time, landed once touchdown has passed.
        var outcome: FlightStatus? {
            guard let status else { return nil }
            if status == .cancelled || status == .diverted { return status }
            if isDeparted, let target, target <= date { return status }
            return nil
        }
    }

    /// The entries, and when to ask for the next timeline.
    struct Plan {
        var moments: [Moment]
        var reloadAt: Date
    }

    /// The most entries one timeline carries. WidgetKit's daily budget counts reloads, not
    /// entries, so this only bounds the work of rendering ahead.
    static let entryCap = 150

    /// How long a landed flight stays on a widget before the next one takes its place: the same
    /// fifteen minutes `Flight.isCurrentlyRelevant` keeps it in the app's own list.
    static let landedLinger: TimeInterval = 15 * 60

    /// When to look again once nothing on the widget changes with the clock any more. Only a new
    /// snapshot changes it then, and the app reloads the widget when it writes one, so this is a
    /// safety net rather than a schedule.
    static let idleReload: TimeInterval = 6 * 3600

    // MARK: - Which flight, and how it stands

    /// The snapshot's flights, soonest first: `trackedFlights`, or `nextFlight` alone in a
    /// snapshot that has no list.
    static func flights(in snapshot: WidgetSnapshot?) -> [WidgetSnapshot.FlightInfo] {
        guard let snapshot else { return [] }
        return snapshot.trackedFlights.isEmpty ? [snapshot.nextFlight].compactMap { $0 } : snapshot.trackedFlights
    }

    /// Still on the widget at `date`: until fifteen minutes past touchdown. A flight with no
    /// arrival time has no end the widget can see, so it stays until the app writes it away.
    static func isShowing(_ flight: WidgetSnapshot.FlightInfo, at date: Date) -> Bool {
        guard let arrival = flight.bestArrival else { return true }
        return arrival.addingTimeInterval(landedLinger) > date
    }

    /// The flight on the widget at `date`: the picked one while it's still showing, otherwise the
    /// soonest still showing. So a landed flight gives way to the next one, or to the empty state,
    /// without waiting for the app to run.
    static func flight(in flights: [WidgetSnapshot.FlightInfo], preferring selectedID: UUID?, at date: Date) -> WidgetSnapshot.FlightInfo? {
        let showing = flights.filter { isShowing($0, at: date) }
        if let selectedID, let match = showing.first(where: { $0.id == selectedID }) {
            return match
        }
        return showing.first
    }

    /// `flight` as it stands at `date`, every field worked out for that moment rather than for
    /// the moment the timeline was built.
    static func moment(_ flight: WidgetSnapshot.FlightInfo?, at date: Date) -> Moment {
        let isDeparted = (flight?.bestDeparture ?? .distantFuture) <= date
        return Moment(
            date: date,
            flight: flight,
            status: flight?.status.projected(departure: flight?.bestDeparture, arrival: flight?.bestArrival, now: date),
            isDeparted: isDeparted,
            target: isDeparted ? flight?.bestArrival : flight?.bestDeparture,
            delaySeconds: delaySeconds(of: flight, isDeparted: isDeparted),
            progress: progress(for: flight, at: date)
        )
    }

    /// The delay of the leg still to come: departure's before take-off, arrival's after (FLT-24).
    /// The one figure an older snapshot stored was chosen when it was written, and kept showing
    /// the departure delay for the rest of the flight; it is still read when it is all there is.
    static func delaySeconds(of flight: WidgetSnapshot.FlightInfo?, isDeparted: Bool) -> Int? {
        guard let flight else { return nil }
        guard flight.departureDelaySeconds != nil || flight.arrivalDelaySeconds != nil else { return flight.delaySeconds }
        return isDeparted ? flight.arrivalDelaySeconds : flight.departureDelaySeconds
    }

    /// Entries on the minute marks before every take-off and touchdown in the snapshot (see
    /// `TimeMath.countdownMoments`), plus one at each hand-over fifteen minutes after a
    /// touchdown, each worked out for its own date. Every flight's marks are there, not only the
    /// first one's, because the next flight can take over within the same timeline.
    ///
    /// Reloads when the entries run out if there is more to count after them, and otherwise only
    /// after `idleReload`. A run that ended with nothing to show used to ask again immediately
    /// (`.atEnd` on a single entry) or every fifteen minutes, spending the budget on the same
    /// answer all day.
    static func plan(_ flights: [WidgetSnapshot.FlightInfo], preferring selectedID: UUID?, from now: Date) -> Plan {
        let targets = flights.flatMap { [$0.bestDeparture, $0.bestArrival].compactMap { $0 } }
        let handovers = flights.compactMap { $0.bestArrival?.addingTimeInterval(landedLinger) }
        let horizon: TimeInterval = 3 * 3600

        var dates = Set(TimeMath.countdownMoments(to: targets, from: now, horizon: horizon))
        dates.formUnion(handovers.filter { $0 > now && $0 <= now.addingTimeInterval(horizon) })
        let sorted = Array(dates.sorted().prefix(entryCap))

        let moments = sorted.map { moment(flight(in: flights, preferring: selectedID, at: $0), at: $0) }
        let last = sorted.last ?? now
        let moreToCome = (targets + handovers).contains { $0 > last }
        let reloadAt = moreToCome ? max(last, now.addingTimeInterval(60)) : now.addingTimeInterval(idleReload)
        return Plan(moments: moments, reloadAt: reloadAt)
    }

    // MARK: - Flight Tracking

    /// The soonest flight, as it stands at each entry.
    static func trackingPlan(_ snapshot: WidgetSnapshot?, from now: Date) -> Plan {
        plan(flights(in: snapshot), preferring: nil, from: now)
    }

    /// The Flight Tracking widget at one moment.
    static func trackingMoment(_ snapshot: WidgetSnapshot?, at date: Date) -> Moment {
        moment(flight(in: flights(in: snapshot), preferring: nil, at: date), at: date)
    }

    /// "Departs in" or "Lands in", over the time left — and nothing once there is no time left.
    /// "Lands in" over "Landed" read as a countdown to something that had already happened.
    static func countdownLabel(isDeparted: Bool, target: Date?, at date: Date) -> String? {
        guard let target, target > date else { return nil }
        return isDeparted ? "Lands in" : "Departs in"
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

    /// The user's picked flight while it's still showing, otherwise the soonest — so an
    /// unconfigured widget, or one whose flight has landed or been removed, shows the nearest
    /// flight. Counts to take-off, then on to touchdown, within the one timeline.
    static func countdownPlan(_ snapshot: WidgetSnapshot?, preferring selectedID: UUID?, from now: Date) -> Plan {
        plan(flights(in: snapshot), preferring: selectedID, from: now)
    }
}
