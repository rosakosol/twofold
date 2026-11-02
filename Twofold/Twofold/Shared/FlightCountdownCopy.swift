//
//  FlightCountdownCopy.swift
//  Twofold
//
//  The Flight Countdown widget's words when there is nothing to count down to.
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
    /// The large line: the time left, or what stands in for it.
    static func headline(hasFlight: Bool, remaining: String?) -> String {
        if let remaining { return remaining }
        return hasFlight ? "—" : "No flight"
    }

    /// The line under it.
    static func caption(hasFlight: Bool, hasTarget: Bool, isDeparted: Bool, destinationCity: String?) -> String {
        guard hasTarget else { return hasFlight ? "Time not set yet" : "No upcoming trip" }
        return isDeparted ? "until \(destinationCity ?? "arrival")" : "until departure"
    }

    /// The Lock Screen's one-line forms, which have room for the flight number and little else.
    static func accessoryLine(flightNumber: String?, remaining: String?, joiner: String) -> String? {
        guard let flightNumber else { return nil }
        guard let remaining else { return "\(flightNumber) · time not set" }
        return "\(flightNumber)\(joiner)\(remaining)"
    }
}
