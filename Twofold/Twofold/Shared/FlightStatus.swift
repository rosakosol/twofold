//
//  FlightStatus.swift
//  Twofold
//
//  Shared with LiveActivitiesExtension (see the "Twofold" folder's membership exception for
//  that target in project.pbxproj) — the Live Activity's ContentState carries a raw
//  FlightStatus.RawValue, and the widget needs this enum's display/icon logic to render it.
//  `semanticColor` (which depends on `Theme`, main-app-only) stays behind in Flight.swift.
//

import Foundation

enum FlightStatus: String, Hashable, Codable, CaseIterable {
    case scheduled
    case boarding
    case departed
    case inAir = "in_air"
    case landingSoon = "landing_soon"
    case landed
    case arrived
    case delayed
    case cancelled
    case diverted

    var emotionalHeadline: String {
        switch self {
        case .scheduled: "Getting ready to fly ✈️"
        case .boarding: "Boarding now ✈️"
        case .departed: "They're on their way ✈️"
        case .inAir: "On the way"
        case .landingSoon: "Almost there"
        case .landed: "They've landed"
        case .arrived: "They've arrived safely"
        case .delayed: "Running a little late"
        case .cancelled: "Flight cancelled"
        case .diverted: "Flight diverted"
        }
    }

    /// Short badge label — deliberately distinct wording from `emotionalHeadline`, which is
    /// for the big header moment; this is for compact chips/cards.
    var displayLabel: String {
        switch self {
        case .scheduled: "Scheduled"
        case .boarding: "Boarding"
        case .departed: "Departed"
        case .inAir: "En route"
        case .landingSoon: "Landing soon"
        case .landed: "Landed"
        case .arrived: "Arrived"
        case .delayed: "Delayed"
        case .cancelled: "Cancelled"
        case .diverted: "Diverted"
        }
    }

    var icon: String {
        switch self {
        case .scheduled: "clock"
        case .boarding: "figure.walk.arrival"
        case .departed: "airplane.departure"
        case .inAir: "airplane"
        case .landingSoon: "airplane.arrival"
        case .landed, .arrived: "checkmark.circle.fill"
        case .delayed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle.fill"
        case .diverted: "arrow.triangle.branch"
        }
    }

    var isActivelyTracked: Bool {
        [.boarding, .departed, .inAir, .landingSoon].contains(self)
    }

    /// Terminal statuses — once reached, a flight is done being actively tracked (whether it
    /// landed successfully or not).
    var isTerminal: Bool {
        [.landed, .arrived, .cancelled, .diverted].contains(self)
    }
}
