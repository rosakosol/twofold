//
//  FlightCountdownCopy.swift
//  Twofold
//
//  The Flight Countdown widget's words, worked out from one timeline moment.
//
//  "No upcoming trip" and "No flight" used to show whenever the widget had no target time — which
//  includes a flight that exists and simply has no departure or arrival time yet. The card named a
//  real flight in its header and then said there was no trip (3-flights-NEW-2). A flight with no
//  time now says that, and only a widget with no flight at all says there isn't one.
//
//  Shared with LiveActivitiesExtension (see the "Twofold" folder's membership exception for that
//  target in project.pbxproj), so the wording is testable from the app's tests.
//

import Foundation

nonisolated enum FlightCountdownCopy {
    typealias Moment = FlightWidgetTimeline.Moment

    /// The large line: the time left, or what stands in for it. Once there is nothing left to
    /// count, what the flight came to — "Landed", "Cancelled", "Diverted" — rather than "0m"
    /// (FLT-21).
    static func headline(_ moment: Moment) -> String {
        guard moment.flight != nil else { return "No flight" }
        if let outcome = moment.outcome { return outcome.displayLabel }
        return moment.target != nil ? remaining(moment) : "—"
    }

    /// The line under it.
    static func caption(_ moment: Moment) -> String {
        guard let flight = moment.flight else { return "No upcoming trip" }
        switch moment.outcome {
        case .cancelled?, .diverted?: return "flight to \(flight.destinationCity)"
        case .some: return "in \(flight.destinationCity)"
        case nil: break
        }
        guard moment.target != nil else { return "Time not set yet" }
        return moment.isDeparted ? "until \(flight.destinationCity)" : "until departure"
    }

    /// The Lock Screen's one-line forms, which have room for the flight number and little else.
    static func accessoryLine(_ moment: Moment, joiner: String) -> String {
        guard let flightNumber = moment.flight?.flightNumber else { return "No tracked flight" }
        if let outcome = moment.outcome { return "\(flightNumber) · \(outcome.displayLabel)" }
        guard moment.target != nil else { return "\(flightNumber) · time not set" }
        return "\(flightNumber)\(joiner)\(remaining(moment))"
    }

    /// The small Lock Screen circle's single unit — "8d"/"2h"/"45m" rather than the combined form
    /// the other families have room for. Rounds down deliberately: "1d" through the whole of the
    /// last day before departure is a truer thing to glance at than a figure that flickers to "2d"
    /// because 47 hours rounded up. Nil when there is nothing to count, for the symbol instead.
    static func circularLabel(_ moment: Moment) -> String? {
        guard moment.outcome == nil, let target = moment.target else { return nil }
        let remaining = max(0, Int(target.timeIntervalSince(moment.date)))
        if remaining >= 86_400 { return "\(remaining / 86_400)d" }
        if remaining >= 3600 { return "\(remaining / 3600)h" }
        return "\(remaining / 60)m"
    }

    /// The circle's symbol when it has no figure: what the flight came to, or the plane.
    static func circularSymbol(_ moment: Moment) -> String { moment.outcome?.icon ?? "airplane" }

    /// Days once there are any, then hours, then minutes — via the same `TimeMath.compactDuration`
    /// the flight screen's own countdown uses, so the widget and the app never disagree about how
    /// long is left.
    private static func remaining(_ moment: Moment) -> String {
        guard let target = moment.target else { return "—" }
        return TimeMath.compactDuration(target.timeIntervalSince(moment.date))
    }
}
