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
            userID: userID
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
            myAnswered: true, partnerAnswered: true, userID: userID
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
            myAnswered: false, partnerAnswered: false, userID: userID
        )
        #expect(OfflineGameStateCache.restore(for: userID)?.dailyStreak == 40)
        OfflineGameStateCache.clear()
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
