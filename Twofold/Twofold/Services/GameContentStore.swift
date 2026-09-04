//
//  GameContentStore.swift
//  Twofold
//
//  Every deck and every question, on the device.
//
//  Games were the one part of the app that needed a connection for all of it. The deck list, the
//  round content, and the session tying them together were each a separate backend call, so with
//  no network the Games hub had nothing to show and nothing to open — on the flight, which is
//  exactly when a couple has hours and nothing to do.
//
//  Two layers, in this order:
//
//  1. `GameContentSeed.json` in the app bundle — produced by `scripts/export-game-content.py`,
//     ~534 KB for 191 decks and ~2,000 rows. This is what makes a device that has *never* been
//     online still able to play.
//  2. A disk cache refreshed from the backend whenever the app is online. Content is added
//     server-side between app releases (there are several "grow the decks" migrations), so the
//     seed goes stale on its own; this is what keeps a shipped build current without waiting for
//     the App Store.
//
//  The cache wins whenever it exists, because it is by definition never older than the seed. It is
//  written whole or not at all — a partial deck list would silently hide decks.
//

import Foundation

enum GameContentStore {

    // MARK: - What a decoded seed or cache holds

    /// Mirrors the export script's output, which is PostgREST's own column naming.
    private struct Payload: Codable {
        var version: Int
        var decks: [DeckRow]
        var content: [String: [ContentRow]]
    }

    private struct DeckRow: Codable {
        var id: UUID
        var topic: String
        var gameType: String
        var title: String
        var emoji: String
        var tier: String
        var sortOrder: Int
        var questionCount: Int

        enum CodingKeys: String, CodingKey {
            case id, topic, title, emoji, tier
            case gameType = "game_type"
            case sortOrder = "sort_order"
            case questionCount = "question_count"
        }
    }

    /// One row from any of the four content tables. They're decoded into a single shape rather
    /// than four, because which columns are present is decided by the game type of the deck the
    /// row belongs to, and the app only ever asks for a deck's rows knowing that type already.
    private struct ContentRow: Codable {
        var id: UUID
        var deckID: UUID
        var category: String?
        var tier: String?
        // trivia
        var question: String?
        var options: [String]?
        var correctAnswer: String?
        var explanation: String?
        var difficulty: String?
        // more likely
        var prompt: String?
        // this or that
        var optionA: String?
        var optionB: String?
        // deep conversations
        var topic: String?

        enum CodingKeys: String, CodingKey {
            case id, category, tier, question, options, explanation, difficulty, prompt, topic
            case deckID = "deck_id"
            case correctAnswer = "correct_answer"
            case optionA = "option_a"
            case optionB = "option_b"
        }
    }

    // MARK: - Loading

    private static let cacheURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("GameContent.json")
    }()

    /// Decoded once and held, because every Games-hub render asks for the deck list and decoding
    /// 2,000 rows on each of those would be felt.
    private nonisolated(unsafe) static var loaded: Payload?
    private static let lock = NSLock()

    private static func payload() -> Payload? {
        lock.lock()
        defer { lock.unlock() }
        if let loaded { return loaded }

        // Application Support, not Caches: this is the offline copy of content the app cannot
        // re-derive without a network, so letting the system reclaim it would take away the one
        // thing that makes games work on a plane.
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(Payload.self, from: data) {
            loaded = cached
            return cached
        }
        guard let url = Bundle.main.url(forResource: "GameContentSeed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let seed = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        loaded = seed
        return seed
    }

    // MARK: - Reading

    /// Every active deck, in the order the Games hub shows them — the same order and filter
    /// `fetchGameDecks()` applies, so the offline list is not a different list.
    static func decks() -> [GameDeck] {
        guard let payload = payload() else { return [] }
        return payload.decks.compactMap { row in
            guard let gameType = GameType(rawValue: row.gameType) else { return nil }
            return GameDeck(
                id: row.id,
                topic: row.topic,
                gameType: gameType,
                title: row.title,
                emoji: row.emoji,
                tier: row.tier,
                sortOrder: row.sortOrder,
                questionCount: row.questionCount
            )
        }
    }

    /// A deck's rounds, ordered by content id.
    ///
    /// The order is arbitrary but must be *stable*, because it decides the round numbers a locally
    /// started session uses. It deliberately doesn't try to match what `start_deck_session` would
    /// have chosen — that RPC's `array_agg` has no `order by`, so there is no order to match. The
    /// set is the same, which is what reconciliation relies on: answers are replayed by content id,
    /// never by round number.
    static func content(forDeck deckID: UUID, gameType: GameType) -> [GameRoundContent] {
        guard let payload = payload(), let rows = payload.content[gameType.rawValue] else { return [] }
        return rows
            .filter { $0.deckID == deckID }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .compactMap { row in content(from: row, gameType: gameType) }
    }

    private static func content(from row: ContentRow, gameType: GameType) -> GameRoundContent? {
        let category = row.category ?? ""
        let tier = row.tier ?? "plus"
        switch gameType {
        case .triviaBattle:
            guard let question = row.question, let options = row.options,
                  let correctAnswer = row.correctAnswer else { return nil }
            return .trivia(TriviaQuestion(
                id: row.id, category: category, question: question, options: options,
                correctAnswer: correctAnswer, explanation: row.explanation,
                difficulty: row.difficulty, active: true, tier: tier
            ))
        case .moreLikely:
            guard let prompt = row.prompt else { return nil }
            return .moreLikely(MoreLikelyPrompt(
                id: row.id, prompt: prompt, active: true, category: category, tier: tier
            ))
        case .thisOrThat:
            guard let optionA = row.optionA, let optionB = row.optionB else { return nil }
            return .thisOrThat(ThisOrThatPrompt(
                id: row.id, optionA: optionA, optionB: optionB, active: true,
                category: category, tier: tier
            ))
        case .deepConversations:
            guard let topic = row.topic else { return nil }
            return .deepConversation(DeepConversationTopic(
                id: row.id, topic: topic, active: true, category: category, tier: tier
            ))
        }
    }

    // MARK: - Refreshing

    /// Replaces the whole cache with a freshly fetched payload.
    ///
    /// Takes the encoded payload rather than model values because the backend already returns
    /// exactly this shape — the same PostgREST column names the export script writes. Round-tripping
    /// it through `GameDeck`/`GameRoundContent` and back would mean two conversions that have to
    /// agree with each other for content to survive, and the only thing that could come of that is
    /// a column quietly dropped on the way through.
    ///
    /// Rejects anything that doesn't decode, or that has no decks: overwriting a working cache
    /// with an empty one would take games away offline, which is the failure this whole file
    /// exists to prevent.
    @discardableResult
    static func store(payload data: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode(Payload.self, from: data),
              !decoded.decks.isEmpty else { return false }
        do {
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            return false
        }
        lock.lock()
        loaded = decoded
        lock.unlock()
        return true
    }

    /// Whether a refreshed copy has ever been stored — the seed alone doesn't count. Lets the
    /// refresh run on a schedule rather than on every foreground, while still fetching promptly
    /// on the first launch after an install.
    static var hasCachedCopy: Bool {
        FileManager.default.fileExists(atPath: cacheURL.path)
    }

    static var cacheAge: TimeInterval? {
        guard let modified = try? FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date
        else { return nil }
        return Date().timeIntervalSince(modified)
    }

    /// Sign-out and account deletion — the next person on this device gets the bundled seed back,
    /// not whatever the last account's tier could see.
    static func clear() {
        try? FileManager.default.removeItem(at: cacheURL)
        lock.lock()
        loaded = nil
        lock.unlock()
    }
}
