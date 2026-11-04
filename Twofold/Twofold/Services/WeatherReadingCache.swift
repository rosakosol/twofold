//
//  WeatherReadingCache.swift
//  Twofold
//
//  The last weather the Home time card showed for each place, so a launch can open on it.
//
//  `HomeView` held its readings in `@State` only, so every cold launch drew the card with no
//  weather — the clear sky for the hour, no temperature, no conditions — for the seconds a
//  WeatherKit round trip takes, and then flashed to the real sky. A reading from earlier in the
//  hour is a better first frame than a sky that claims nothing and then changes its mind.
//
//  Only while it is fresh. A reading older than `maxAge` is not shown at all: the card waits for
//  the live one in its loading state rather than presenting this morning's temperature as now.
//

import Foundation

enum WeatherReadingCache {
    /// The same hour `WidgetSnapshotWriter.reusableWeather` trusts a reading for. Temperatures and
    /// conditions rarely move far inside it; past it the card would be guessing.
    static let maxAge: TimeInterval = 3600

    private static let key = "weather.lastReadings"

    struct Entry: Codable, Equatable {
        var symbolName: String
        var temperatureC: Double
        var isDaylight: Bool?
        var fetchedAt: Date

        var reading: CurrentWeatherReading {
            CurrentWeatherReading(symbolName: symbolName, temperatureC: temperatureC, isDaylight: isDaylight)
        }
    }

    /// Keyed by the place's spot rather than its id, so the same city reached through a cached
    /// `Place` and a freshly fetched one finds the same reading.
    private static func storageKey(for place: Place) -> String {
        "\(place.spot.latitude),\(place.spot.longitude)"
    }

    static func record(_ reading: CurrentWeatherReading, for place: Place, at date: Date = .now, defaults: UserDefaults = .standard) {
        var entries = load(defaults).filter { date.timeIntervalSince($0.value.fetchedAt) < maxAge }
        entries[storageKey(for: place)] = Entry(
            symbolName: reading.symbolName, temperatureC: reading.temperatureC, isDaylight: reading.isDaylight, fetchedAt: date
        )
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }

    /// The reading to open the card on, or nil when there is none young enough to show.
    ///
    /// Falls back to the widgets' copy of the partner's weather — written by
    /// `WidgetSnapshotWriter`, on the same hourly cadence — so the first launch after this cache
    /// existed, or one after only the widget refresh ran, still has something to start from.
    static func reading(for place: Place, now: Date = .now, defaults: UserDefaults = .standard, snapshot: WidgetSnapshot? = WidgetSnapshot.read()) -> CurrentWeatherReading? {
        if let entry = load(defaults)[storageKey(for: place)], isFresh(entry.fetchedAt, now: now) {
            return entry.reading
        }
        guard let shared = WidgetSnapshotWriter.reusableWeather(from: snapshot, partnerCity: place.displayCity, now: now) else { return nil }
        return CurrentWeatherReading(symbolName: shared.symbolName, temperatureC: shared.temperatureC, isDaylight: shared.isDaylight)
    }

    /// Strictly younger than `maxAge`, and never from the future — a clock set back is not a
    /// reason to trust a reading indefinitely.
    static func isFresh(_ fetchedAt: Date, now: Date = .now) -> Bool {
        let age = now.timeIntervalSince(fetchedAt)
        return age >= 0 && age < maxAge
    }

    /// Home cities are the account's, so this goes with it on sign-out.
    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    private static func load(_ defaults: UserDefaults) -> [String: Entry] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return entries
    }
}
