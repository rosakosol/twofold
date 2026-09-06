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
        var isReunion: Bool

        // Optional, not fabricated to `.now()` when unknown — a flight the provider hasn't
        // supplied any schedule data for yet must render as "not available" on the Lock Screen,
        // same as `FlightTrackingView` already does for the same nil case, rather than showing a
        // live, ticking "now" as if it were a real departure/arrival time.
        var scheduledDeparture: Date?
        var scheduledArrival: Date?
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
    }

    var flightID: UUID
    /// The person on the plane.
    var travelerName: String
    /// The other half of the couple — whoever the traveller is flying towards on a reunion.
    var partnerName: String
    /// Whether the traveller is the person whose phone this is.
    ///
    /// A Live Activity is started locally on each device, so each one knows its own viewer and the
    /// two devices get their own wording for the same flight. Without this the card addressed
    /// everyone as though they were the one waiting at home, and a traveller watching their own
    /// flight was told they were on the way to themselves.
    var viewerIsTraveler: Bool

    var flightNumber: String
    var airlineName: String?
    var originCode: String
    var originCity: String?
    var destinationCode: String
    var destinationCity: String?

    // Decoded leniently, so an Activity already running when this shipped still loads.
    //
    // iOS keeps a running Activity's attributes encoded on disk and decodes them again on the next
    // launch. Synthesised `Decodable` requires every key, so adding two non-optional fields would
    // make an already-running card fail to decode — it would vanish from `Activity.activities`, the
    // app would think nothing was running and start a second one, and the orphan would sit on the
    // Lock Screen beside it. These default instead: an older card keeps the wording it launched
    // with, and `LiveActivityManager` replaces it on the next sync.
    init(flightID: UUID, travelerName: String, partnerName: String, viewerIsTraveler: Bool, flightNumber: String, airlineName: String?, originCode: String, originCity: String?, destinationCode: String, destinationCity: String?) {
        self.flightID = flightID
        self.travelerName = travelerName
        self.partnerName = partnerName
        self.viewerIsTraveler = viewerIsTraveler
        self.flightNumber = flightNumber
        self.airlineName = airlineName
        self.originCode = originCode
        self.originCity = originCity
        self.destinationCode = destinationCode
        self.destinationCity = destinationCity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        flightID = try container.decode(UUID.self, forKey: .flightID)
        travelerName = try container.decode(String.self, forKey: .travelerName)
        partnerName = try container.decodeIfPresent(String.self, forKey: .partnerName) ?? ""
        viewerIsTraveler = try container.decodeIfPresent(Bool.self, forKey: .viewerIsTraveler) ?? false
        flightNumber = try container.decode(String.self, forKey: .flightNumber)
        airlineName = try container.decodeIfPresent(String.self, forKey: .airlineName)
        originCode = try container.decode(String.self, forKey: .originCode)
        originCity = try container.decodeIfPresent(String.self, forKey: .originCity)
        destinationCode = try container.decode(String.self, forKey: .destinationCode)
        destinationCity = try container.decodeIfPresent(String.self, forKey: .destinationCity)
    }
}
#endif
