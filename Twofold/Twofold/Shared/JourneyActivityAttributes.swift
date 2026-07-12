//
//  JourneyActivityAttributes.swift
//  Twofold
//
//  Describes the Live Activity shown on the Lock Screen / Dynamic Island while a tracked
//  flight is active. Shared with LiveActivitiesExtension (see the "Twofold" folder's
//  membership exception for that target in project.pbxproj) — the main app calls
//  `Activity<JourneyActivityAttributes>.request(...)`, the widget extension renders it via
//  `ActivityConfiguration(for: JourneyActivityAttributes.self)`.
//
//  `ContentState` is pushed by the server (see supabase/functions/_shared/apns.ts's
//  sendLiveActivityUpdate) as well as updated locally — every Date/Date? field here is decoded
//  by Swift's default JSONDecoder as seconds since the Cocoa reference date (2001-01-01), NOT
//  Unix epoch. The server-side payload builder converts accordingly; see apns.ts's
//  toCocoaTimestamp helper.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit

struct JourneyActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: FlightStatus.RawValue
        var progress: Double
        var timeRemainingLabel: String
        var isReunion: Bool

        var scheduledDeparture: Date
        var scheduledArrival: Date
        var estimatedDeparture: Date?
        var estimatedArrival: Date?
        var actualDeparture: Date?
        var actualArrival: Date?

        var gateOrigin: String?
        var gateDestination: String?
        var terminalOrigin: String?
        var terminalDestination: String?
        var baggageClaim: String?

        var departureDelayMinutes: Int?
        var arrivalDelayMinutes: Int?

        var lastUpdatedAt: Date
    }

    var flightID: UUID
    var travelerName: String
    var flightNumber: String
    var airlineName: String?
    var originCode: String
    var originCity: String?
    var destinationCode: String
    var destinationCity: String?
}
#endif
