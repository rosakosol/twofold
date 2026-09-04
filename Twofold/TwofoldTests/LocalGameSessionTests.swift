//
//  LocalGameSessionTests.swift
//  TwofoldTests
//
//  Starting a deck with no connection, and the mapping that gets those answers home.
//
//  The risky part isn't creating the session — it's that the round numbers used offline are the
//  app's own. `start_deck_session` builds the real session's rounds with an unordered `array_agg`,
//  so submitting an offline answer by round number would attach it to whichever question happened
//  to land in that slot: silently, plausibly, and wrong. Everything here is about the content id
//  being what actually carries an answer across.
//
//  Every test that touches the stores holds `LocalGameSessionTestLock` — `.serialized` orders these
//  against each other but not against `GameSessionStoreOfflineTests`, which writes the same keys.
//

import Testing
import Foundation
@testable import Twofold

@Suite(.serialized)
struct LocalGameSessionTests {

    private func deck(
        tier: String = "plus",
        gameType: GameType = .deepConversations
    ) -> GameDeck {
        GameDeck(
            id: UUID(), topic: "Travel", gameType: gameType, title: "Long Haul",
            emoji: "✈️", tier: tier, sortOrder: 1, questionCount: 3
        )
    }

    /// A real deck from the shipped catalogue — offline sessions are built from it, so a test
    /// using a made-up deck id would prove nothing about whether that path works.
    private func catalogueDeck(gameType: GameType = .deepConversations) throws -> GameDeck {
        try #require(
            GameContentStore.decks().first { $0.gameType == gameType && $0.tier != "premium" },
            "no \(gameType.rawValue) deck in the bundled catalogue"
        )
    }

    // MARK: - Creating one

    @Test("a deck from the catalogue becomes a playable session")
    func createsFromCatalogue() throws {
        try LocalGameSessionTestLock.withExclusiveStores {
            let deck = try catalogueDeck()
            let session = try #require(
                LocalGameSessionStore.create(deck: deck, effectiveTier: "plus", hasPartner: true)
            )
            #expect(session.deckID == deck.id)
            #expect(session.totalRounds == deck.questionCount)
            #expect(session.rounds().count == session.totalRounds)
            #expect(
                Set(session.contentIDs).count == session.contentIDs.count,
                "a question appears twice in one session"
            )
        }
    }

    @Test("it survives being written and read back")
    func persists() throws {
        try LocalGameSessionTestLock.withExclusiveStores {
            let deck = try catalogueDeck()
            let created = try #require(
                LocalGameSessionStore.create(deck: deck, effectiveTier: "plus", hasPartner: true)
            )
            let reloaded = try #require(LocalGameSessionStore.session(id: created.id))
            #expect(reloaded.contentIDs == created.contentIDs, "the round order has to survive a relaunch")
        }
    }

    /// Reopening the deck must resume, not start again — a second session would renumber the
    /// rounds under answers already queued against the first.
    @Test("reopening the same deck finds the session already in progress")
    func resumesRatherThanRestarts() throws {
        try LocalGameSessionTestLock.withExclusiveStores {
            let deck = try catalogueDeck()
            let first = try #require(
                LocalGameSessionStore.create(deck: deck, effectiveTier: "plus", hasPartner: true)
            )
            #expect(LocalGameSessionStore.session(forDeck: deck.id)?.id == first.id)
        }
    }

    // MARK: - The refusals, applied before the game rather than after it

    /// `start_deck_session` raises on both of these. Letting someone play offline anyway would
    /// mean the answers sync into a rejection and vanish once the game is already over.
    @Test("a Premium deck can't be started offline by a Plus couple")
    func premiumDeckIsRefused() {
        #expect(!LocalGameSessionStore.canStart(deck: deck(tier: "premium"), effectiveTier: "plus", hasPartner: true))
        #expect(LocalGameSessionStore.canStart(deck: deck(tier: "premium"), effectiveTier: "premium", hasPartner: true))
    }

    @Test("Who's More Likely To can't be started without a partner")
    func moreLikelyNeedsAPartner() {
        let moreLikely = deck(gameType: .moreLikely)
        #expect(!LocalGameSessionStore.canStart(deck: moreLikely, effectiveTier: "plus", hasPartner: false))
        #expect(LocalGameSessionStore.canStart(deck: moreLikely, effectiveTier: "plus", hasPartner: true))
    }

    @Test("a deck with no content on the device isn't started")
    func unknownDeckIsRefused() {
        LocalGameSessionTestLock.withExclusiveStores {
            #expect(LocalGameSessionStore.create(deck: deck(), effectiveTier: "plus", hasPartner: true) == nil)
        }
    }

    // MARK: - Carrying answers across

    /// The whole point. A local session's round 1 and the real session's round 1 need not hold the
    /// same question, so an answer has to travel by content id.
    @Test("an answer maps to the round holding its question, not to its old round number")
    func answersMapByContent() throws {
        try LocalGameSessionTestLock.withExclusiveStores {
            let deck = try catalogueDeck()
            let local = try #require(
                LocalGameSessionStore.create(deck: deck, effectiveTier: "plus", hasPartner: true)
            )
            let answeredContent = try #require(local.contentID(forRound: 1))

            // The real session, with its rounds in a different order — the case the mapping exists
            // for.
            let realRounds = local.contentIDs.reversed().enumerated().map { index, contentID in
                GameSessionRound(
                    id: UUID(), sessionID: UUID(), roundNumber: index + 1,
                    contentID: contentID, discussionStatus: nil
                )
            }
            var roundForContent: [UUID: Int] = [:]
            for round in realRounds { roundForContent[round.contentID] = round.roundNumber }

            let mapped = try #require(roundForContent[answeredContent])
            #expect(mapped == local.totalRounds, "round 1 offline is the last round in this reversed session")
            #expect(realRounds.first { $0.roundNumber == mapped }?.contentID == answeredContent)
        }
    }

    @Test("a queued answer remembers which question it was for")
    func queuedAnswerCarriesContent() throws {
        let contentID = UUID()
        let pending = PendingGameResponse(
            sessionID: UUID(), roundNumber: 2, responderID: UUID(),
            answerValue: "yes", isCorrect: nil, contentID: contentID
        )
        let data = try JSONEncoder().encode(pending)
        let decoded = try JSONDecoder().decode(PendingGameResponse.self, from: data)
        #expect(decoded.contentID == contentID)
    }

    /// Answers queued by a build that predates the content id are all for real sessions, where the
    /// round number is already right — they must keep decoding rather than being dropped.
    @Test("answers queued before content ids existed still decode")
    func olderQueuedAnswersStillDecode() throws {
        let json = """
        {"id":"\(UUID().uuidString)","sessionID":"\(UUID().uuidString)","roundNumber":3,\
        "responderID":"\(UUID().uuidString)","answerValue":"blue","queuedAt":760000000}
        """
        let decoded = try JSONDecoder().decode(PendingGameResponse.self, from: Data(json.utf8))
        #expect(decoded.contentID == nil)
        #expect(decoded.roundNumber == 3)
    }

    @Test("removing a session leaves the others alone")
    func removalIsScoped() throws {
        try LocalGameSessionTestLock.withExclusiveStores {
            let deep = try catalogueDeck(gameType: .deepConversations)
            let trivia = try catalogueDeck(gameType: .triviaBattle)
            let a = try #require(LocalGameSessionStore.create(deck: deep, effectiveTier: "plus", hasPartner: true))
            let b = try #require(LocalGameSessionStore.create(deck: trivia, effectiveTier: "plus", hasPartner: true))
            LocalGameSessionStore.remove(id: a.id)
            #expect(LocalGameSessionStore.session(id: a.id) == nil)
            #expect(LocalGameSessionStore.session(id: b.id) != nil)
        }
    }

    /// Signing out has to take queued answers with it: `submitGameResponse` writes as whoever is
    /// signed in *now*, so answers left behind would be submitted as the next person on this
    /// device.
    @Test("clearing takes the queued answers as well as the sessions")
    func clearingRemovesQueuedAnswers() {
        PendingGameResponseStore.add(
            PendingGameResponse(
                sessionID: UUID(), roundNumber: 1, responderID: UUID(),
                answerValue: "mine", isCorrect: nil, contentID: UUID()
            )
        )
        PendingGameResponseStore.clear()
        #expect(PendingGameResponseStore.all().isEmpty)
    }
}
