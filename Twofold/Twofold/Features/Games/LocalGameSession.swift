//
//  LocalGameSession.swift
//  Twofold
//
//  A deck started with no connection, and how it becomes a real one afterwards.
//
//  Starting a deck is `start_deck_session`, a server RPC: it picks the rounds, inserts the session
//  and returns its id. Offline there is no id, so there was nothing to open and nothing to answer
//  against — the answer queue that already existed could only ever hold answers for a session
//  someone had opened while online.
//
//  So the app builds the session itself. The rounds are not a guess: `start_deck_session` uses
//  *every* active row for the deck, and `GameContentStore` has those same rows, so the set is
//  identical. Only the order differs — that RPC's `array_agg` has no `order by`, so there is no
//  order to reproduce — and that is exactly why answers are queued against a **content id** rather
//  than a round number. When the connection returns, the real session is created, its rounds are
//  read back, and each answer is matched to the round holding its content.
//
//  The tier and partner rules are mirrored here rather than trusted to fail later. The RPC rejects
//  a Premium deck for a Plus couple and rejects "Who's More Likely To" with no partner; if the app
//  let someone play one offline anyway, the answers would sync into a rejection and be dropped
//  after the game was already over.
//

import Foundation

struct LocalGameSession: Codable, Identifiable, Equatable {
    let id: UUID
    let deckID: UUID
    let gameType: GameType
    /// Round order. Index + 1 is the round number this session used while offline; the content id
    /// is what survives into the real session.
    let contentIDs: [UUID]
    let createdAt: Date

    var totalRounds: Int { contentIDs.count }

    func contentID(forRound roundNumber: Int) -> UUID? {
        let index = roundNumber - 1
        guard contentIDs.indices.contains(index) else { return nil }
        return contentIDs[index]
    }

    /// The shape `GameSessionStore` renders. `coupleID` is left nil the way the RPC's own solo
    /// branch does — nothing offline reads it, and the real session carries the true value.
    func asSession(initiatorID: UUID) -> GameSession {
        GameSession(
            id: id,
            coupleID: nil,
            gameType: gameType,
            initiatorID: initiatorID,
            status: .active,
            totalRounds: totalRounds,
            isDaily: false,
            deckID: deckID,
            startedAt: createdAt,
            completedAt: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    func rounds() -> [GameSessionRound] {
        contentIDs.enumerated().map { index, contentID in
            GameSessionRound(
                id: UUID(),
                sessionID: id,
                roundNumber: index + 1,
                contentID: contentID,
                discussionStatus: nil
            )
        }
    }
}

enum LocalGameSessionStore {
    private static let key = "localGameSessions"

    static func all() -> [LocalGameSession] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([LocalGameSession].self, from: data)) ?? []
    }

    static func session(id: UUID) -> LocalGameSession? {
        all().first { $0.id == id }
    }

    /// The one already in progress for this deck, so reopening it offline resumes rather than
    /// starting again with a fresh set of round numbers under the same queued answers.
    static func session(forDeck deckID: UUID) -> LocalGameSession? {
        all().first { $0.deckID == deckID }
    }

    static func save(_ session: LocalGameSession) {
        var sessions = all().filter { $0.id != session.id }
        sessions.append(session)
        write(sessions)
    }

    static func remove(id: UUID) {
        write(all().filter { $0.id != id })
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func write(_ sessions: [LocalGameSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - Creating

    /// Builds a playable session from the on-device catalogue, or nil when this deck isn't one the
    /// backend would have let them start anyway.
    static func create(deck: GameDeck, effectiveTier: String?, hasPartner: Bool) -> LocalGameSession? {
        guard canStart(deck: deck, effectiveTier: effectiveTier, hasPartner: hasPartner) else { return nil }
        let content = GameContentStore.content(forDeck: deck.id, gameType: deck.gameType)
        guard !content.isEmpty else { return nil }

        let session = LocalGameSession(
            id: UUID(),
            deckID: deck.id,
            gameType: deck.gameType,
            contentIDs: content.map(\.contentID),
            createdAt: .now
        )
        save(session)
        return session
    }

    /// `start_deck_session`'s own two refusals, applied before the game rather than after it.
    static func canStart(deck: GameDeck, effectiveTier: String?, hasPartner: Bool) -> Bool {
        if deck.tier == "premium" && effectiveTier != "premium" { return false }
        if deck.gameType == .moreLikely && !hasPartner { return false }
        return true
    }
}

private extension GameRoundContent {
    var contentID: UUID { Twofold.contentID(of: self) }
}

/// The content id behind a round, for callers outside this file that hold a `GameRoundContent` and
/// need to key it — `GameSessionStore` rebuilding an offline session's content map, in particular.
func contentID(of content: GameRoundContent) -> UUID {
    switch content {
    case let .trivia(question): question.id
    case let .moreLikely(prompt): prompt.id
    case let .thisOrThat(prompt): prompt.id
    case let .deepConversation(topic): topic.id
    }
}
