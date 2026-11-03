//
//  GamesStateTests.swift
//  TwofoldTests
//
//  The games store, and that reset() leaves nothing of the last couple's games behind.
//

import Foundation
import Testing
@testable import Twofold

@Suite("GamesState")
@MainActor
struct GamesStateTests {

    @Test("reset() clears the streak, today's question and the decks")
    func resetClearsEverything() {
        let games = GamesState()
        games.applyDemoState()
        games.streakRepair = nil
        games.dailyQuestionError = "stale"
        #expect(games.dailyStreak != nil)

        games.reset()

        #expect(games.dailyStreak == nil)
        #expect(games.longestDailyStreak == nil)
        #expect(games.dailyStreakResetsAt == nil)
        #expect(games.streakRepair == nil)
        #expect(games.todaysDailySessionID == nil)
        #expect(games.todaysDailyQuestionText == nil)
        #expect(games.todaysMyAnswered == false)
        #expect(games.todaysPartnerAnswered == false)
        #expect(games.dailyQuestionError == nil)
        #expect(games.gameDecks == nil)
        #expect(games.deckProgress == nil)
        #expect(games.adultContentStatus == nil)
    }

    @Test("The repair offer asks AppModel whether a partner has joined")
    func partnerConnectedComesFromAppModel() {
        let model = AppModel()
        model.session.partnerConnected = true
        #expect(model.games.isPartnerConnected())
        model.session.partnerConnected = false
        #expect(!model.games.isPartnerConnected())
    }
}
