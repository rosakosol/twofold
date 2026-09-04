//
//  GameSessionStoreOfflineTests.swift
//  TwofoldTests
//
//  Playing through a deck with no connection — specifically, that it keeps going.
//
//  "Loads the first screen but subsequent rounds don't load" was the reported half that mattered
//  most: a deck that opens and then stalls is worse than one that never opens, because by then the
//  couple has committed to playing it. Offline, an answer never reaches a server, so the *only*
//  thing moving the game forward is the queued answer being reflected back into `responses` — if
//  that doesn't happen, round one is where the game ends.
//
//  Driven through the store rather than the UI: the Games hub carries 191 decks, and XCUITest
//  times out enumerating that hierarchy long before it could measure anything.
//
//  Every test holds `LocalGameSessionTestLock` — `.serialized` orders these against each other but
//  not against `LocalGameSessionTests`, which writes the same two `UserDefaults` keys.
//

import Testing
import Foundation
@testable import Twofold

@Suite(.serialized)
@MainActor
struct GameSessionStoreOfflineTests {

    private let me = UUID()

    /// Mirrors what `GameSessionStore.loadLocalSession` builds, without needing a signed-in user.
    private func store(for local: LocalGameSession) -> GameSessionStore {
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

    private func localSession() throws -> LocalGameSession {
        let deck = try #require(
            GameContentStore.decks().first { $0.gameType == .deepConversations && $0.tier != "premium" && $0.questionCount >= 3 }
        )
        return try #require(LocalGameSessionStore.create(deck: deck, effectiveTier: "plus", hasPartner: true))
    }

    /// Answering offline records against a session that has no server row, so the answer only
    /// exists in the queue — this is the step that has to move the game on.
    private func answerOffline(_ store: GameSessionStore, round: Int, local: LocalGameSession) {
        let pending = PendingGameResponse(
            sessionID: local.id,
            roundNumber: round,
            responderID: me,
            answerValue: "talked about it",
            isCorrect: nil,
            contentID: local.contentID(forRound: round)
        )
        PendingGameResponseStore.add(pending)
        store.responses.append(
            GameResponse(
                id: pending.id, sessionID: pending.sessionID, roundNumber: pending.roundNumber,
                responderID: pending.responderID, answerValue: pending.answerValue,
                isCorrect: pending.isCorrect, createdAt: pending.queuedAt
            )
        )
    }

    @Test("every round is playable offline, not just the first")
    func playsThroughTheWholeDeck() throws {
        try LocalGameSessionTestLock.withExclusiveStores {
            let local = try localSession()
            let store = store(for: local)

            #expect(store.rounds.count == local.totalRounds)
            for round in 1...local.totalRounds {
                let current = try #require(
                    store.nextUnansweredRound(myID: me),
                    "the game stalled at round \(round) of \(local.totalRounds)"
                )
                #expect(current.roundNumber == round)
                #expect(store.roundContent[current.contentID] != nil, "round \(round) has no question to show")
                answerOffline(store, round: round, local: local)
        }
        #expect(store.nextUnansweredRound(myID: me) == nil, "the deck should be finished")
        }
    }

    /// Reopening after the app was killed mid-flight: the answers are on disk, the session is
    /// rebuilt from the catalogue, and play has to resume where it stopped rather than at round 1.
    @Test("a deck answered offline resumes where it left off")
    func resumesAfterRelaunch() throws {
        try LocalGameSessionTestLock.withExclusiveStores {
            let local = try localSession()
            let first = store(for: local)

            answerOffline(first, round: 1, local: local)
            answerOffline(first, round: 2, local: local)

            // A fresh store, as after a relaunch — nothing in memory, everything from disk.
            let reopened = store(for: try #require(LocalGameSessionStore.session(id: local.id)))
            for item in PendingGameResponseStore.forSession(local.id) {
                reopened.responses.append(
                    GameResponse(
                        id: item.id, sessionID: item.sessionID, roundNumber: item.roundNumber,
                        responderID: item.responderID, answerValue: item.answerValue,
                        isCorrect: item.isCorrect, createdAt: item.queuedAt
                    )
                )
        }
        #expect(reopened.nextUnansweredRound(myID: me)?.roundNumber == 3)
        }
    }

    /// Every queued answer has to carry the question it was for, or reconciliation can only fall
    /// back to a round number that means nothing in the real session.
    @Test("each queued answer names its question")
    func queuedAnswersCarryContent() throws {
        try LocalGameSessionTestLock.withExclusiveStores {
            let local = try localSession()
            let store = store(for: local)

            for round in 1...3 { answerOffline(store, round: round, local: local) }
            let queued = PendingGameResponseStore.forSession(local.id)
            #expect(queued.count == 3)
            #expect(queued.allSatisfy { $0.contentID != nil })
            #expect(Set(queued.compactMap(\.contentID)).count == 3, "two answers point at the same question")
        }
    }
}
