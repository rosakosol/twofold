//
//  GameMissingContentTests.swift
//  TwofoldTests
//
//  Reported: a new Plus couple opened card decks they had never played and landed on the
//  "you've finished" screen. The decks held premium cards the database hides from Plus, so their
//  rounds had no card, and every game view reads "no card for the next round" as "all answered".
//  The store now says the cards couldn't be loaded instead.
//

import Testing
import Foundation
@testable import Twofold

@Suite(.serialized)
@MainActor
struct GameMissingContentTests {

    private let me = UUID()

    /// A real deck session as `GameSessionStore.loadLocalSession` builds it, every card present.
    private func loadedStore() throws -> GameSessionStore {
        let deck = try #require(
            GameContentStore.decks().first { $0.gameType == .thisOrThat && $0.tier != "premium" && $0.questionCount >= 3 }
        )
        let local = try #require(LocalGameSessionStore.create(deck: deck, effectiveTier: "plus", hasPartner: true))
        let store = GameSessionStore()
        store.session = local.asSession(initiatorID: me)
        store.rounds = local.rounds()
        store.roundContent = Dictionary(
            uniqueKeysWithValues: GameContentStore
                .content(forDeck: local.deckID, gameType: local.gameType)
                .map { (contentID(of: $0), $0) }
        )
        store.responses = []
        return store
    }

    @Test("a deck with every card loaded plays normally")
    func everyCardPresent() throws {
        LocalGameSessionStore.clear()
        let store = try loadedStore()
        store.flagMissingContent()
        #expect(store.errorMessage == nil)
        #expect(store.displayedRound(myID: me).map(store.content(for:)) != nil)
    }

    @Test("a round with no card is reported, not shown as finished")
    func missingCardIsAnError() throws {
        LocalGameSessionStore.clear()
        let store = try loadedStore()
        let first = try #require(store.rounds.first)
        store.roundContent[first.contentID] = nil

        store.flagMissingContent()

        #expect(store.errorMessage != nil, "every game view shows the finished screen for a round with no card unless this is set")
    }

    @Test("a finished game is left to show its results")
    func finishedGameIsLeftAlone() throws {
        LocalGameSessionStore.clear()
        let store = try loadedStore()
        let first = try #require(store.rounds.first)
        store.roundContent[first.contentID] = nil
        store.session?.status = .completed

        store.flagMissingContent()

        #expect(store.errorMessage == nil)
    }
}
