//
//  OfflineDataCache.swift
//  Twofold
//
//  Last-known trips/flights/memories, written to disk on every successful load so the app has
//  real content to show when there's no network — the case this app is most used in (a plane).
//
//  Companion to `OfflineSessionCache`, kept separate on purpose: that one holds the small
//  identity/entitlement facts `RootView` needs to decide *which screen to show at all*, and is
//  read on the critical launch path. This is the bulk travel data behind it, and a failure to
//  read it should never be able to keep someone out of the app.
//
//  A JSON file rather than UserDefaults — this can be megabytes for a couple with a long history,
//  which is well past what UserDefaults is meant to hold. Same Application Support location
//  `PendingMemoryStore`/`PendingTripStore` already use for their own on-disk manifests.
//
//  Deliberately not a general offline-write layer: everything here is read-only replay of what the
//  server last said. Creating things offline is already handled separately (and properly, with
//  real sync-on-reconnect) by PendingMemoryStore/PendingTripStore and GameSessionStore's queue.
//

import Foundation

enum OfflineDataCache {
    private struct Snapshot: Codable {
        var trips: [Trip]
        var flights: [Flight]
        var memories: [Memory]
        var userID: String?
        var recordedAt: Date
    }

    /// Matches `OfflineSessionCache`'s window so the two can't disagree about whether the cached
    /// session is still worth trusting.
    private static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("OfflineDataCache.json")
    }

    static func record(trips: [Trip], flights: [Flight], memories: [Memory], userID: UUID?) {
        let snapshot = Snapshot(
            trips: trips,
            flights: flights,
            memories: memories,
            userID: userID?.uuidString,
            recordedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Account-scoped and age-bounded for the same reasons as `OfflineSessionCache.restore` — a
    /// previous user of this device must never see their trips resurface under a new account.
    static func restore(for userID: UUID?) -> (trips: [Trip], flights: [Flight], memories: [Memory])? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        guard let userID, snapshot.userID == userID.uuidString else { return nil }
        guard Date().timeIntervalSince(snapshot.recordedAt) < maxAge else { return nil }
        return (snapshot.trips, snapshot.flights, snapshot.memories)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
