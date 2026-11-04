//
//  WidgetWeatherFreshnessTests.swift
//  TwofoldTests
//
//  The partner's weather on the widgets was never refetched while the app was in use.
//
//  `WidgetSnapshotWriter` reuses the last reading for an hour rather than asking WeatherKit on every
//  refresh, and it measured that hour from the snapshot's `writtenAt`. But every refresh writes a
//  new snapshot, and refreshes come every minute or two around a tracked flight and on every
//  foreground, so `writtenAt` was always recent and the reading it carried forward was never old
//  enough to replace. The weather is timed by when it was fetched now.
//

import Foundation
import Testing
@testable import Twofold

struct WidgetWeatherFreshnessTests {

    private static let now = Date(timeIntervalSince1970: 1_793_000_000)

    private static func snapshot(city: String = "Rome", writtenAgo: TimeInterval, weatherFetchedAgo: TimeInterval?) -> WidgetSnapshot {
        WidgetSnapshot(
            myName: "Sam", partnerName: "Alex", partnerCity: city,
            partnerWeather: WidgetSnapshot.WeatherInfo(
                symbolName: "sun.max.fill", temperatureC: 21, isDaylight: true,
                fetchedAt: weatherFetchedAgo.map { now.addingTimeInterval(-$0) }
            ),
            writtenAt: now.addingTimeInterval(-writtenAgo)
        )
    }

    @Test("a two-hour-old reading is fetched again, however recently the snapshot was rewritten")
    func oldReadingInARecentSnapshotIsStale() {
        let previous = Self.snapshot(writtenAgo: 60, weatherFetchedAgo: 2 * 3600)
        #expect(WidgetSnapshotWriter.reusableWeather(from: previous, partnerCity: "Rome", now: Self.now) == nil)
    }

    @Test("a reading from ten minutes ago is reused")
    func recentReadingIsReused() {
        let previous = Self.snapshot(writtenAgo: 60, weatherFetchedAgo: 600)
        #expect(WidgetSnapshotWriter.reusableWeather(from: previous, partnerCity: "Rome", now: Self.now)?.temperatureC == 21)
    }

    @Test("a reading of unknown age, from before readings were timed, is fetched again")
    func untimedReadingIsStale() {
        let previous = Self.snapshot(writtenAgo: 60, weatherFetchedAgo: nil)
        #expect(WidgetSnapshotWriter.reusableWeather(from: previous, partnerCity: "Rome", now: Self.now) == nil)
    }

    @Test("a reading for the city the partner used to be in is not reused")
    func otherCityIsNotReused() {
        let previous = Self.snapshot(city: "Paris", writtenAgo: 60, weatherFetchedAgo: 60)
        #expect(WidgetSnapshotWriter.reusableWeather(from: previous, partnerCity: "Rome", now: Self.now) == nil)
    }

    /// Timing readings means each refetch writes a new `fetchedAt`. The same weather, fetched
    /// again, is not a reason to spend a widget reload.
    @Test("refetching the same weather reloads no widget")
    func sameReadingReloadsNothing() {
        let before = Self.snapshot(writtenAgo: 0, weatherFetchedAgo: 2 * 3600)
        let after = Self.snapshot(writtenAgo: 0, weatherFetchedAgo: 0)
        #expect(WidgetReloadPlan.kinds(from: before, to: after).isEmpty)
    }
}
