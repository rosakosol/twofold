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
//    actually gets. It carries its own `questionRecordedAt` for that test rather than reading the
//    snapshot's `recordedAt`, which any write moves — including the streak-only write that happens
//    on every foreground, before the Games hub has asked for a question at all.
//  - Deck progress is what the Games hub's topic bars are built from, and it decays slowest of
//    the three: a deck you finished stays finished. Kept for the full window, because "you have
//    completed nothing" is a worse thing to tell someone than a count that's a day behind.
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
        /// Keyed by deck id as a string — `[UUID: T]` encodes as a flat alternating array, which
        /// round-trips but reads as nonsense in the file.
        var deckProgress: [String: DeckProgress]?
        var userID: String?
        var recordedAt: Date
        /// When the *question* was recorded, which is not when the snapshot was.
        ///
        /// `recordedAt` moves on every write, and a streak-only write carries the question forward
        /// without bringing its date — so on the first launch of a new day, `refreshDailyStreak()`
        /// was enough to re-stamp yesterday's question as today's. The Games hub then painted it
        /// from cache and swapped it for the real one when the network answered, which is the flash
        /// this exists to stop.
        ///
        /// Optional because a snapshot written before this field existed has no value for it, and
        /// the safe reading of "no date" is "not today".
        var questionRecordedAt: Date?
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
        deckProgress: [UUID: DeckProgress]?,
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
            deckProgress: deckProgress.map { Dictionary(uniqueKeysWithValues: $0.map { ($0.key.uuidString, $0.value) }) }
                ?? existing?.deckProgress,
            userID: userID?.uuidString,
            recordedAt: Date(),
            // Stamped only by a write that actually carries a question. A streak-only write keeps
            // the question — deliberately, see above — and must keep its original date with it,
            // or carrying it forward silently ages into claiming it is today's.
            questionRecordedAt: questionText == nil ? existing?.questionRecordedAt : Date()
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        // Today's question text and the streak. Same reasoning as OfflineDataCache, including
        // why the directory is left alone.
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        DataProtectionMigration.excludeFromBackup(fileURL)
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

        // The question's own date, not the snapshot's. See `questionRecordedAt`.
        let isToday = snapshot.questionRecordedAt.map(Calendar.current.isDateInToday) ?? false
        return Restored(
            dailyStreak: snapshot.dailyStreak,
            longestDailyStreak: snapshot.longestDailyStreak,
            dailyStreakResetsAt: snapshot.dailyStreakResetsAt,
            questionText: isToday ? snapshot.questionText : nil,
            questionSessionID: isToday ? snapshot.questionSessionID : nil,
            myAnswered: isToday && snapshot.myAnswered,
            partnerAnswered: isToday && snapshot.partnerAnswered,
            deckProgress: snapshot.deckProgress.map {
                Dictionary(uniqueKeysWithValues: $0.compactMap { key, value in
                    UUID(uuidString: key).map { ($0, value) }
                })
            }
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
        var deckProgress: [UUID: DeckProgress]?
    }
}
