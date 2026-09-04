//
//  OfflineGameStateCacheTests.swift
//  TwofoldTests
//
//  The streak and today's question, which decay on different clocks.
//
//  A streak is the one number in the app nobody wants to see wrong, and offline it read as zero —
//  not "unknown", zero, next to a "resets in" countdown. The question is different: it's assigned
//  per day by the backend, so yesterday's is not a stale version of today's, it's the wrong one.
//

import Testing
import Foundation
@testable import Twofold

@Suite(.serialized)
struct OfflineGameStateCacheTests {

    private let userID = UUID()

    private func record(
        streak: Int? = 40,
        longest: Int? = 55,
        question: String? = "What are you most grateful for this week?",
        sessionID: UUID? = UUID(),
        mine: Bool = true,
        partner: Bool = false,
        progress: [UUID: DeckProgress]? = nil,
        userID: UUID
    ) {
        OfflineGameStateCache.record(
            dailyStreak: streak,
            longestDailyStreak: longest,
            dailyStreakResetsAt: Date().addingTimeInterval(3600),
            questionText: question,
            questionSessionID: sessionID,
            myAnswered: mine,
            partnerAnswered: partner,
            deckProgress: progress,
            userID: userID
        )
    }

    private func completedProgress() -> DeckProgress {
        DeckProgress(
            sessionID: UUID(), status: .completed, totalRounds: 10,
            myAnswered: 10, partnerAnswered: 10, completedAt: Date()
        )
    }

    @Test("the streak and today's question both come back")
    func roundTrips() throws {
        OfflineGameStateCache.clear()
        record(userID: userID)
        let restored = try #require(OfflineGameStateCache.restore(for: userID))
        #expect(restored.dailyStreak == 40)
        #expect(restored.longestDailyStreak == 55)
        #expect(restored.questionText?.isEmpty == false)
        #expect(restored.myAnswered)
        #expect(!restored.partnerAnswered)
        OfflineGameStateCache.clear()
    }

    /// `refreshDailyStreak()` runs on its own from `refreshAll()` and knows nothing about the
    /// question. A plain overwrite there would drop today's question on every refresh — which is
    /// most of them, since the streak refreshes far more often than the question does.
    @Test("refreshing only the streak doesn't erase today's question")
    func streakWriteKeepsTheQuestion() throws {
        OfflineGameStateCache.clear()
        record(userID: userID)
        OfflineGameStateCache.record(
            dailyStreak: 41, longestDailyStreak: 55, dailyStreakResetsAt: nil,
            questionText: nil, questionSessionID: nil,
            myAnswered: true, partnerAnswered: true, deckProgress: nil, userID: userID
        )
        let restored = try #require(OfflineGameStateCache.restore(for: userID))
        #expect(restored.dailyStreak == 41)
        #expect(restored.questionText?.isEmpty == false, "the question was dropped by a streak-only write")
        OfflineGameStateCache.clear()
    }

    /// A `nil` streak means "not loaded yet", not "zero" — writing one must not wipe a known count.
    @Test("a write with no streak yet keeps the last known one")
    func nilStreakDoesNotClear() throws {
        OfflineGameStateCache.clear()
        record(userID: userID)
        OfflineGameStateCache.record(
            dailyStreak: nil, longestDailyStreak: nil, dailyStreakResetsAt: nil,
            questionText: "later question", questionSessionID: nil,
            myAnswered: false, partnerAnswered: false, deckProgress: nil, userID: userID
        )
        #expect(OfflineGameStateCache.restore(for: userID)?.dailyStreak == 40)
        OfflineGameStateCache.clear()
    }

    /// The Games hub counts every topic bar from this. Without it, an offline hub told a couple
    /// who had finished forty decks that they had finished none — the same shape of wrong as the
    /// streak reading zero.
    @Test("deck progress survives, so the topic bars aren't all empty offline")
    func deckProgressRoundTrips() throws {
        OfflineGameStateCache.clear()
        let deckID = UUID()
        record(progress: [deckID: completedProgress()], userID: userID)

        let restored = try #require(OfflineGameStateCache.restore(for: userID))
        let progress = try #require(restored.deckProgress?[deckID])
        #expect(progress.isCompleted)
        #expect(progress.myAnswered == 10)
        OfflineGameStateCache.clear()
    }

    /// `refreshDailyStreak()` writes without knowing about decks, exactly as it writes without
    /// knowing about today's question — neither may erase the other.
    @Test("a streak-only write keeps deck progress")
    func streakWriteKeepsDeckProgress() throws {
        OfflineGameStateCache.clear()
        let deckID = UUID()
        record(progress: [deckID: completedProgress()], userID: userID)
        OfflineGameStateCache.record(
            dailyStreak: 41, longestDailyStreak: 55, dailyStreakResetsAt: nil,
            questionText: nil, questionSessionID: nil,
            myAnswered: true, partnerAnswered: true, deckProgress: nil, userID: userID
        )
        #expect(OfflineGameStateCache.restore(for: userID)?.deckProgress?[deckID] != nil)
        OfflineGameStateCache.clear()
    }

    /// The two decay on different clocks, which is the whole reason they're treated separately: a
    /// deck you finished stays finished, but yesterday's question is not a stale version of
    /// today's — it's the wrong one.
    @Test("a day later, deck progress is still there and yesterday's question is gone")
    func progressOutlivesTheQuestion() throws {
        OfflineGameStateCache.clear()
        let deckID = UUID()
        record(progress: [deckID: completedProgress()], userID: userID)
        try rewindRecording(byDays: 1)

        let restored = try #require(
            OfflineGameStateCache.restore(for: userID),
            "a day old is well inside the two-day window"
        )
        #expect(restored.deckProgress?[deckID] != nil, "a finished deck doesn't unfinish overnight")
        #expect(restored.questionText == nil, "yesterday's question is the wrong question, not a stale one")
        OfflineGameStateCache.clear()
    }

    /// Ages the stored snapshot by editing `recordedAt` in place — the only way to test a
    /// day-boundary rule without waiting for one.
    private func rewindRecording(byDays days: Int) throws {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineGameStateCache.json")
        var json = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        let recordedAt = try #require(json["recordedAt"] as? Double)
        json["recordedAt"] = recordedAt - Double(days) * 24 * 60 * 60
        try JSONSerialization.data(withJSONObject: json).write(to: url)
    }

    @Test("another account's streak is never restored")
    func accountScoped() {
        OfflineGameStateCache.clear()
        record(userID: userID)
        #expect(OfflineGameStateCache.restore(for: UUID()) == nil)
        OfflineGameStateCache.clear()
    }

    @Test("clearing leaves nothing behind")
    func clearing() {
        record(userID: userID)
        OfflineGameStateCache.clear()
        #expect(OfflineGameStateCache.restore(for: userID) == nil)
    }
}
