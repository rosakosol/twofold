//
//  WeatherReadingCacheTests.swift
//  TwofoldTests
//
//  The Home time card opened on no weather at every launch and flashed to the real sky a few
//  seconds later. It now opens on the last reading — but only one young enough to stand for now,
//  because a card showing this morning's temperature as current is worse than one still loading.
//

import Foundation
import Testing
@testable import Twofold

struct WeatherReadingCacheTests {

    private static let now = Date(timeIntervalSince1970: 1_793_000_000)
    private static let rome = Place(city: "Rome", country: "Italy", latitude: 41.9028, longitude: 12.4964)
    private static let reading = CurrentWeatherReading(symbolName: "cloud.rain", temperatureC: 14, isDaylight: true)

    /// A suite of its own per test, so these never touch the app's real cache or each other's.
    private func freshDefaults() -> UserDefaults {
        let name = "WeatherReadingCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("a reading from earlier in the hour is what the card opens on")
    func freshReadingIsReturned() {
        let defaults = freshDefaults()
        WeatherReadingCache.record(Self.reading, for: Self.rome, at: Self.now.addingTimeInterval(-20 * 60), defaults: defaults)

        let cached = WeatherReadingCache.reading(for: Self.rome, now: Self.now, defaults: defaults, snapshot: nil)
        #expect(cached == Self.reading)
    }

    @Test("a reading over an hour old is not shown as current")
    func staleReadingIsNotReturned() {
        let defaults = freshDefaults()
        WeatherReadingCache.record(Self.reading, for: Self.rome, at: Self.now.addingTimeInterval(-61 * 60), defaults: defaults)

        #expect(WeatherReadingCache.reading(for: Self.rome, now: Self.now, defaults: defaults, snapshot: nil) == nil)
    }

    /// A clock set back would otherwise make a reading look young for as long as it stayed back.
    @Test("a reading dated in the future is not trusted")
    func futureReadingIsNotFresh() {
        #expect(!WeatherReadingCache.isFresh(Self.now.addingTimeInterval(120), now: Self.now))
        #expect(WeatherReadingCache.isFresh(Self.now, now: Self.now))
        #expect(!WeatherReadingCache.isFresh(Self.now.addingTimeInterval(-WeatherReadingCache.maxAge), now: Self.now))
    }

    /// Keyed by where the place is, not its id: a cached `Place` and the freshly fetched one for the
    /// same city must find the same reading.
    @Test("the same spot under another place id finds the reading")
    func matchesBySpot() {
        let defaults = freshDefaults()
        WeatherReadingCache.record(Self.reading, for: Self.rome, at: Self.now, defaults: defaults)
        let sameSpot = Place(city: "Roma", country: "Italia", latitude: 41.9028, longitude: 12.4964)
        let paris = Place(city: "Paris", country: "France", latitude: 48.8566, longitude: 2.3522)

        #expect(WeatherReadingCache.reading(for: sameSpot, now: Self.now, defaults: defaults, snapshot: nil) == Self.reading)
        #expect(WeatherReadingCache.reading(for: paris, now: Self.now, defaults: defaults, snapshot: nil) == nil)
    }

    /// The widgets keep their own copy of the partner's weather. With nothing of its own yet — the
    /// first launch after this cache existed — the card starts from that one, on the same terms.
    @Test("falls back to the widgets' fresh copy of the partner's weather")
    func fallsBackToWidgetSnapshot() {
        let defaults = freshDefaults()
        func snapshot(fetchedAgo: TimeInterval) -> WidgetSnapshot {
            WidgetSnapshot(
                myName: "Sam", partnerName: "Alex", partnerCity: Self.rome.displayCity,
                partnerWeather: WidgetSnapshot.WeatherInfo(
                    symbolName: "sun.max", temperatureC: 25, isDaylight: true, fetchedAt: Self.now.addingTimeInterval(-fetchedAgo)
                ),
                writtenAt: Self.now
            )
        }

        let fresh = WeatherReadingCache.reading(for: Self.rome, now: Self.now, defaults: defaults, snapshot: snapshot(fetchedAgo: 600))
        #expect(fresh?.temperatureC == 25)
        #expect(WeatherReadingCache.reading(for: Self.rome, now: Self.now, defaults: defaults, snapshot: snapshot(fetchedAgo: 7200)) == nil)
    }

    @Test("recording prunes readings that have aged out")
    func recordingPrunesStaleEntries() {
        let defaults = freshDefaults()
        let paris = Place(city: "Paris", country: "France", latitude: 48.8566, longitude: 2.3522)
        WeatherReadingCache.record(Self.reading, for: paris, at: Self.now.addingTimeInterval(-3 * 3600), defaults: defaults)
        WeatherReadingCache.record(Self.reading, for: Self.rome, at: Self.now, defaults: defaults)

        // Read back at a moment when Paris's reading was still young: it was pruned
        // anyway, so it is gone rather than merely stale.
        let earlier = Self.now.addingTimeInterval(-3 * 3600 + 60)
        #expect(WeatherReadingCache.reading(for: paris, now: earlier, defaults: defaults, snapshot: nil) == nil)
        #expect(WeatherReadingCache.reading(for: Self.rome, now: Self.now, defaults: defaults, snapshot: nil) == Self.reading)
    }

    @Test("clearing empties it")
    func clearEmpties() {
        let defaults = freshDefaults()
        WeatherReadingCache.record(Self.reading, for: Self.rome, at: Self.now, defaults: defaults)
        WeatherReadingCache.clear(defaults: defaults)
        #expect(WeatherReadingCache.reading(for: Self.rome, now: Self.now, defaults: defaults, snapshot: nil) == nil)
    }
}
