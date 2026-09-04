//
//  OfflineGameStateCache.swift
//  Twofold
//
//  The daily streak and today's question, kept so the Games hub isn't blank without a network.
//
//  Separate from `OfflineDataCache` because it's written at a different moment. That one is filled
//  when the couple is adopted; these two only exist after `startOrResumeDailyQuestion()` and
//  `refreshDailyStreak()`, which run when the Games hub appears. Folding them into one snapshot
//  would mean whichever wrote last dropped the other's fields.
//
//  Both are day-scoped, and treated differently because they decay differently:
//
//  - Today's question is only today's. Restored only on the day it was recorded, because on any
//    later day the honest answer is that the app doesn't know yet which question it will be — the
//    backend assigns it, and guessing would show a question that isn't the one the couple
//    actually gets.
//  - The streak is a count that was true when it was written. It stays restorable for two days:
//    the number can go stale if a day is missed while offline, but so can the online app between
//    refreshes, and showing a streak that's a day behind is closer to the truth than showing zero
//    to someone on a 40-day run.
//

import Foundation

enum OfflineGameStateCache {

    private struct Snapshot: Codable {
        var dailyStreak: Int?
        var longestDailyStreak: Int?
        var dailyStreakResetsAt: Date?
        var questionText: String?
        var questionSessionID: UUID?
        var myAnswered: Bool
        var partnerAnswered: Bool
        var userID: String?
        var recordedAt: Date
    }

    /// Two days, not thirty: a streak is a daily thing, and one older than this says more about
    /// how long it's been since the app was opened than about the couple.
    private static let maxStreakAge: TimeInterval = 2 * 24 * 60 * 60

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("OfflineGameStateCache.json")
    }

    static func record(
        dailyStreak: Int?,
        longestDailyStreak: Int?,
        dailyStreakResetsAt: Date?,
        questionText: String?,
        questionSessionID: UUID?,
        myAnswered: Bool,
        partnerAnswered: Bool,
        userID: UUID?
    ) {
        // Merged rather than replaced. `refreshDailyStreak()` runs on its own from `refreshAll()`
        // and knows nothing about the question, so a plain write there would erase today's
        // question every time the app refreshed.
        let existing = read()
        let snapshot = Snapshot(
            dailyStreak: dailyStreak ?? existing?.dailyStreak,
            longestDailyStreak: longestDailyStreak ?? existing?.longestDailyStreak,
            dailyStreakResetsAt: dailyStreakResetsAt ?? existing?.dailyStreakResetsAt,
            questionText: questionText ?? existing?.questionText,
            questionSessionID: questionSessionID ?? existing?.questionSessionID,
            myAnswered: myAnswered,
            partnerAnswered: partnerAnswered,
            userID: userID?.uuidString,
            recordedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func read() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// Account-scoped for the same reason as every other cache here — the next person to sign in
    /// on this device must not inherit a stranger's streak.
    static func restore(for userID: UUID?) -> Restored? {
        guard let snapshot = read(), let userID, snapshot.userID == userID.uuidString else { return nil }
        guard Date().timeIntervalSince(snapshot.recordedAt) < maxStreakAge else { return nil }

        let isToday = Calendar.current.isDateInToday(snapshot.recordedAt)
        return Restored(
            dailyStreak: snapshot.dailyStreak,
            longestDailyStreak: snapshot.longestDailyStreak,
            dailyStreakResetsAt: snapshot.dailyStreakResetsAt,
            questionText: isToday ? snapshot.questionText : nil,
            questionSessionID: isToday ? snapshot.questionSessionID : nil,
            myAnswered: isToday && snapshot.myAnswered,
            partnerAnswered: isToday && snapshot.partnerAnswered
        )
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    struct Restored {
        var dailyStreak: Int?
        var longestDailyStreak: Int?
        var dailyStreakResetsAt: Date?
        var questionText: String?
        var questionSessionID: UUID?
        var myAnswered: Bool
        var partnerAnswered: Bool
    }
}
