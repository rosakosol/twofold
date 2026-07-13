//
//  WidgetSnapshot.swift
//  Twofold
//
//  Everything a Home Screen widget needs to render, written by the main app (which is the only
//  thing that talks to Supabase/WeatherKit) into the shared App Group container, then read
//  synchronously and locally by each widget's TimelineProvider — no network/auth inside the
//  extension except DoodlePadWidget (public bucket, see PublicStorageURL.swift). Key is
//  versioned so a future shape change can't crash an old cached read.
//
//  Shared with LiveActivitiesExtension (see the "Twofold" folder's membership exception for
//  that target in project.pbxproj).
//

import Foundation

/// `CLLocationCoordinate2D` itself isn't `Codable` — this is just its two doubles, boxed for
/// JSON storage in the snapshot.
struct WidgetCoordinate: Codable {
    var latitude: Double
    var longitude: Double
}

struct WidgetSnapshot: Codable {
    struct FlightInfo: Codable {
        /// Lets a tapped widget deep-link straight to this flight's tracking screen
        /// (twofold://flight/{id}) instead of just opening the app.
        var id: UUID
        var status: FlightStatus
        var originCity: String
        var destinationCity: String
        var bestDeparture: Date?
        var bestArrival: Date?
        /// Whichever leg is currently relevant (departure delay pre-takeoff, arrival delay
        /// once airborne) — used by FlightTrackingWidget/FlightCountdownWidget, nil when on
        /// time/unknown.
        var delaySeconds: Int?
        var flightNumber: String
        var airlineName: String?
        var originCoordinate: WidgetCoordinate?
        var destinationCoordinate: WidgetCoordinate?
        /// Live in-flight position if the provider has one; nil pre-departure/post-arrival, in
        /// which case FlightTrackingWidget parks the marker at the origin/destination instead
        /// (mirrors FlightMapView's own pre-departure "avatar parked at origin" behavior).
        var positionCoordinate: WidgetCoordinate?
        /// 0...1, same as Flight.progress — reused directly rather than recomputed in the
        /// extension, since bestDeparture/bestArrival alone don't capture the provider's actual
        /// live-position-based progress for an in-flight leg.
        var progress: Double
        /// nil = no traveler set on this flight. true = the current user is travelling; false =
        /// the partner is. Drives which cached avatar (if either) rides the progress rail.
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

    /// Sourced from FlightStats(trips:couple:) (PassportView.swift) — pure/sync/cheap, computed
    /// in WidgetSnapshotWriter rather than duplicating that aggregation logic here.
    struct TravelStats: Codable {
        var flightCount: Int
        var countryCount: Int
        var totalDistanceKm: Double
        var nextTripDestination: String?
        var nextTripDate: Date?
    }

    /// Needed alongside coupleID/partnerID for DoodleSideBySideWidget to build *my* public
    /// drawing-pad URL, the same way DoodlePadWidget already builds the partner's.
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
    var travelStats: TravelStats?
    /// Needed by DoodlePadWidget to build the partner's public drawing-pad URL itself
    /// (PublicStorageURL.swift) — the one widget allowed its own network call.
    var coupleID: UUID?
    var partnerID: UUID?
    var writtenAt: Date
    /// When GlobeWidget's cached image was last (re)rendered — carried forward across ordinary
    /// snapshot writes so WidgetSnapshotWriter can gate the expensive MKMapSnapshotter call to
    /// roughly once/24h instead of running it on every refresh.
    var globeImageWrittenAt: Date?

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
