//
//  WidgetSnapshot.swift
//  Twofold
//
//  Everything a Home Screen widget needs to render, written by the main app (which is the only
//  thing that talks to Supabase/WeatherKit) into the shared App Group container, then read
//  synchronously and locally by each widget's TimelineProvider — no network/auth inside the
//  extension except DrawingPadWidget (public bucket, see PublicStorageURL.swift). Key is
//  versioned so a future shape change can't crash an old cached read.
//
//  Shared with LiveActivitiesExtension (see the "Twofold" folder's membership exception for
//  that target in project.pbxproj).
//

import Foundation

struct WidgetSnapshot: Codable {
    struct FlightInfo: Codable {
        /// Lets a tapped widget deep-link straight to this flight's tracking screen
        /// (twofold://flight/{id}) instead of just opening the app.
        var id: UUID
        var status: FlightStatus
        var originCity: String
        var destinationCity: String
        /// IATA/ICAO airport code (e.g. "MEL") — FlightAirport.displayCode's same fallback
        /// chain, shown alongside the city name rather than instead of it.
        var originCode: String
        var destinationCode: String
        var bestDeparture: Date?
        var bestArrival: Date?
        /// Whichever leg is currently relevant (departure delay pre-takeoff, arrival delay once
        /// airborne) — used by FlightTrackingWidget's delay badge, nil when on time/unknown.
        var delaySeconds: Int?
        var flightNumber: String
        /// 0...1, same as Flight.progress — reused directly rather than recomputed in the
        /// extension, since bestDeparture/bestArrival alone don't capture the provider's actual
        /// live-position-based progress for an in-flight leg. Drives FlightTrackingWidget's
        /// progress rail.
        var progress: Double
        /// nil = no traveler set on this flight. true = the current user is travelling; false =
        /// the partner is. Drives which cached avatar (if either) shows next to the countdown.
        var travelerIsMe: Bool?
    }

    struct MemoryInfo: Codable {
        /// Lets a tapped widget deep-link straight to this memory (twofold://memory/{id})
        /// instead of just opening the Memories tab.
        var id: UUID
        var title: String
        var date: Date
    }

    struct WeatherInfo: Codable {
        var symbolName: String
        var temperatureC: Double
    }

    /// Days together is deliberately not stored here — every widget that needs it already
    /// recomputes it live from `anniversaryDate` (see DaysTogetherWidget), so it stays correct
    /// without waiting for the next snapshot write, the same reason `anniversaryDate` itself is
    /// stored raw rather than a precomputed count.
    struct RelationshipStats: Codable {
        var memoryCount: Int
        var tripCount: Int
    }

    /// Needed alongside coupleID/partnerID for DrawingPadWidget's Medium side-by-side layout to
    /// build *my* public drawing-pad URL, the same way it already builds the partner's.
    var myID: UUID?
    var myName: String
    var partnerName: String
    var partnerCity: String?
    var partnerTimeZoneIdentifier: String?
    var anniversaryDate: Date?
    /// "plus"/"premium"/nil — nil means no active subscription at all (never locked out of
    /// free-tier widgets, same "plus is the safe default" rule as AppModel.subscriptionTier).
    /// Replaces the old single isSubscriptionActive bool now that widgets gate Plus vs. Premium
    /// content the same way Games does (see WidgetTier.swift).
    var subscriptionTier: String?
    var nextFlight: FlightInfo?
    var latestMemory: MemoryInfo?
    var partnerWeather: WeatherInfo?
    var relationshipStats: RelationshipStats?
    /// Needed by DrawingPadWidget to build the partner's public drawing-pad URL itself
    /// (PublicStorageURL.swift) — the one widget allowed its own network call.
    var coupleID: UUID?
    var partnerID: UUID?
    var writtenAt: Date

    private static let suiteName = "group.com.orangefinch.Twofold"
    /// Bumped from v1 when isSubscriptionActive was replaced by subscriptionTier — the key is
    /// versioned specifically so a shape change like this can't crash an old cached read.
    private static let key = "widgetSnapshot.v2"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    static func read() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
