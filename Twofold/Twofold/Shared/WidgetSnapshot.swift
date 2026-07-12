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

struct WidgetSnapshot: Codable {
    struct FlightInfo: Codable {
        var status: String
        var originCity: String
        var destinationCity: String
        var bestDeparture: Date?
        var bestArrival: Date?
    }

    struct MemoryInfo: Codable {
        var title: String
        var date: Date
    }

    struct WeatherInfo: Codable {
        var symbolName: String
        var temperatureC: Double
    }

    var partnerName: String
    var partnerCity: String?
    var partnerTimeZoneIdentifier: String?
    var anniversaryDate: Date?
    var isSubscriptionActive: Bool
    var nextFlight: FlightInfo?
    var latestMemory: MemoryInfo?
    var partnerWeather: WeatherInfo?
    /// Needed by DoodlePadWidget to build the partner's public drawing-pad URL itself
    /// (PublicStorageURL.swift) — the one widget allowed its own network call.
    var coupleID: UUID?
    var partnerID: UUID?
    var writtenAt: Date

    private static let suiteName = "group.com.orangefinch.Twofold"
    private static let key = "widgetSnapshot.v1"

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
