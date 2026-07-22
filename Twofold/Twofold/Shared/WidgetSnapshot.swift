//
//  WidgetSnapshot.swift
//  Twofold
//
//  Everything a Home Screen widget needs to render, written by the main app (which is the only
//  thing that talks to Supabase/WeatherKit) into the shared App Group container, then read
//  synchronously and locally by each widget's TimelineProvider. `drawing-pads` is a private
//  Storage bucket the extension has no session to sign anything against itself, so
//  DrawingPadWidget still does its own live network fetch (unlike every other image, which the
//  main app downloads and caches — see WidgetImageCache), just against the pre-signed URLs
//  cached here instead of a permanent public one. Key is versioned so a future shape change
//  can't crash an old cached read.
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

    /// The soonest upcoming trip (`AppModel.upcomingTrips.first`, same source as Home's
    /// "next reunion" card and `nextReunionDaysToGo`) — not tied to a tracked flight, since a
    /// trip's own departure date is what actually marks "when we'll be together", and not every
    /// trip has (or needs) an AeroAPI-tracked flight attached. `departureDate` stored raw, not a
    /// precomputed day-count, so TripCountdownWidget stays correct without waiting on a fresh
    /// snapshot write — same reasoning as `anniversaryDate`.
    struct ReunionInfo: Codable {
        var departureDate: Date
        var destinationCity: String
        var isReunionTrip: Bool
    }

    /// Kept for DrawingPadWidget's Medium side-by-side layout, which needs to know whose pad is
    /// "mine" vs. "partner's" alongside the two signed URLs below.
    var myID: UUID?
    var myName: String
    var partnerName: String
    var myCity: String?
    var partnerCity: String?
    var partnerTimeZoneIdentifier: String?
    /// Pre-formatted per the device's actual measurement-system preference (km/mi) —
    /// `MeasurementPreference` reads `UserDefaults.standard`, which isn't shared with this
    /// extension's process, so the label has to be built app-side (WidgetSnapshotWriter) rather
    /// than recomputed here from a raw distance.
    var distanceLabel: String?
    var anniversaryDate: Date?
    /// "plus"/"premium"/nil — nil means no active subscription at all (never locked out of
    /// free-tier widgets, same "plus is the safe default" rule as AppModel.subscriptionTier).
    /// Replaces the old single isSubscriptionActive bool now that widgets gate Plus vs. Premium
    /// content the same way Games does (see WidgetTier.swift).
    var subscriptionTier: String?
    var nextFlight: FlightInfo?
    /// Every currently-relevant flight (`AppModel.activeOrUpcomingFlights`), not just the
    /// soonest — feeds `TrackedFlightQuery`'s picker for the configurable Flight Countdown
    /// widget, which needs to offer the user more than one option. `nextFlight` above stays the
    /// "just give me the soonest one" convenience every other widget already relies on.
    var trackedFlights: [FlightInfo] = []
    var nextReunion: ReunionInfo?
    var latestMemory: MemoryInfo?
    var partnerWeather: WeatherInfo?
    var relationshipStats: RelationshipStats?
    /// Needed by DrawingPadWidget to identify which pads belong to this couple, alongside
    /// `mySignedDrawingPadURL`/`partnerSignedDrawingPadURL` below.
    var coupleID: UUID?
    var partnerID: UUID?
    /// Signed `drawing-pads` Storage URLs, refreshed by `WidgetSnapshotWriter` (a 48-hour expiry
    /// — generous enough to survive a couple of days between app opens). DrawingPadWidget fetches
    /// these live itself rather than reading cached bytes the way every other widget image does,
    /// so a partner's fresh doodle can still show up without either device's main app needing to
    /// run again first — the underlying storage object is overwritten in place at the same path,
    /// so a not-yet-expired signed URL keeps resolving to whatever's currently there.
    var mySignedDrawingPadURL: URL?
    var partnerSignedDrawingPadURL: URL?
    var writtenAt: Date

    private static let suiteName = "group.com.orangefinch.Twofold"
    /// Bumped from v1 when isSubscriptionActive was replaced by subscriptionTier, from v2 when
    /// trackedFlights was added, and from v3 when the drawing-pad public URLs were replaced by
    /// signed ones — the key is versioned specifically so a shape change like this can't crash an
    /// old cached read.
    private static let key = "widgetSnapshot.v4"

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
