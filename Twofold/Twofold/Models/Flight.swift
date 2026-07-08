//
//  Flight.swift
//  Twofold
//

import Foundation

enum FlightStatus: String, Hashable {
    case scheduled
    case departed
    case inAir
    case landingSoon
    case arrived
    case delayed
    case cancelled
    case diverted

    var emotionalHeadline: String {
        switch self {
        case .scheduled: "Getting ready to fly ✈️"
        case .departed: "They're on their way ✈️"
        case .inAir: "On the way to you ❤️"
        case .landingSoon: "Almost there ❤️"
        case .arrived: "They've landed ❤️"
        case .delayed: "Running a little late"
        case .cancelled: "Flight cancelled"
        case .diverted: "Flight diverted"
        }
    }
}

struct FlightTimelineEvent: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case departed = "Departed"
        case inAir = "In the air"
        case landingSoon = "Landing soon"
        case arrived = "Arriving"
    }

    let id: UUID
    var kind: Kind
    var time: Date
    var isComplete: Bool

    init(id: UUID = UUID(), kind: Kind, time: Date, isComplete: Bool) {
        self.id = id
        self.kind = kind
        self.time = time
        self.isComplete = isComplete
    }
}

struct Flight: Identifiable, Hashable {
    let id: UUID
    var flightNumber: String
    var origin: Place
    var destination: Place
    var status: FlightStatus
    var scheduledDeparture: Date
    var scheduledArrival: Date
    /// 0...1 progress of the flight along its route, used to place the aircraft on the map/progress rail.
    var progress: Double
    var timeline: [FlightTimelineEvent]

    init(
        id: UUID = UUID(),
        flightNumber: String,
        origin: Place,
        destination: Place,
        status: FlightStatus,
        scheduledDeparture: Date,
        scheduledArrival: Date,
        progress: Double,
        timeline: [FlightTimelineEvent]
    ) {
        self.id = id
        self.flightNumber = flightNumber
        self.origin = origin
        self.destination = destination
        self.status = status
        self.scheduledDeparture = scheduledDeparture
        self.scheduledArrival = scheduledArrival
        self.progress = progress
        self.timeline = timeline
    }

    var timeRemaining: TimeInterval {
        max(0, scheduledArrival.timeIntervalSinceNow)
    }
}
