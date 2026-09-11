//
//  GameContentStoreTests.swift
//  TwofoldTests
//
//  The on-device game catalogue: the bundled seed decodes, and a deck's rounds come back.
//
//  This is the kind of thing that fails silently. The seed is written by a Python script from
//  PostgREST's snake_case columns and read by Swift `Codable` — one renamed key and every deck
//  quietly disappears, with no crash and no error, leaving exactly the empty Games hub the file
//  exists to prevent. Nothing in the app would say so, because offline an empty catalogue looks
//  identical to being offline.
//

import Testing
import Foundation
@testable import Twofold

struct GameContentStoreTests {

    /// The seed has to be in the app bundle at all — it's a synchronized resource folder, so a
    /// file added on disk is included automatically, and just as easily excluded by a stray
    /// membership exception.
    @Test("the bundled seed ships with the app")
    func seedIsBundled() throws {
        let url = try #require(
            Bundle.main.url(forResource: "GameContentSeed", withExtension: "json"),
            "no seed in the bundle — games are unavailable on a device that has never been online"
        )
        let size = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        #expect(size > 100_000, "a seed this small is a truncated export, not a catalogue")
    }

    @Test("decks decode from the seed")
    func decksDecode() {
        let decks = GameContentStore.decks()
        #expect(decks.count > 50, "expected the full catalogue, got \(decks.count)")
        #expect(decks.allSatisfy { !$0.title.isEmpty })
        #expect(decks.allSatisfy { $0.questionCount > 0 }, "a deck with no rounds can't be played")
    }

    /// Every deck-based game type must be represented, or one of them is silently missing offline.
    ///
    /// The generated games are not among them, and the exclusion is asserted rather than assumed.
    /// Their content comes from the round's id on the device, so there is no deck to ship and
    /// nothing for `GameContentStore` to hold — writing this as "every case in `GameType`" made
    /// adding sudoku fail a test about the seed file, which was the test being wrong rather than
    /// the seed. Word Guess landed in the same place, which is why this is now a named set: a third
    /// generated game should update one line here, not rediscover the same argument.
    private static let generated: Set<GameType> = [.sudoku, .wordGuess, .wordSearch]

    @Test("every deck-based game type has decks")
    func everyGameTypeIsPresent() {
        let types = Set(GameContentStore.decks().map(\.gameType))
        for gameType in GameType.allCases where !Self.generated.contains(gameType) {
            #expect(types.contains(gameType), "no decks for \(gameType.rawValue)")
        }
        for gameType in Self.generated {
            #expect(!types.contains(gameType), "\(gameType.rawValue) has no curated content — a deck here is a mistake")
        }
    }

    /// The rounds themselves — this is what a locally started session is built from, so an empty
    /// result here is a deck that opens to nothing.
    @Test("a deck's rounds come back, and match its advertised count")
    func contentResolvesForEveryDeck() {
        for deck in GameContentStore.decks() {
            let content = GameContentStore.content(forDeck: deck.id, gameType: deck.gameType)
            #expect(
                content.count == deck.questionCount,
                "\(deck.title): \(content.count) rounds decoded but questionCount says \(deck.questionCount)"
            )
        }
    }

    /// Round numbers for an offline session come from this order, and answers are replayed against
    /// the server by content id — but a wobbling order would still shuffle a session under someone
    /// mid-game, between one launch and the next.
    @Test("round order is stable across calls")
    func orderIsStable() throws {
        let deck = try #require(GameContentStore.decks().first)
        let first = GameContentStore.content(forDeck: deck.id, gameType: deck.gameType)
        let second = GameContentStore.content(forDeck: deck.id, gameType: deck.gameType)
        #expect(first == second)
    }

    /// Trivia is the one type with structure beyond a single string — a decode that dropped
    /// `options` would give a playable-looking question with no answers to pick from.
    @Test("trivia rounds keep their options and correct answer")
    func triviaDecodesFully() throws {
        let deck = try #require(GameContentStore.decks().first { $0.gameType == .triviaBattle })
        let content = GameContentStore.content(forDeck: deck.id, gameType: .triviaBattle)
        let questions: [TriviaQuestion] = content.compactMap {
            if case let .trivia(question) = $0 { return question }
            return nil
        }
        #expect(questions.count == content.count, "some trivia rows failed to decode")
        #expect(questions.allSatisfy { $0.options.count >= 2 })
        #expect(questions.allSatisfy { !$0.correctAnswer.isEmpty })
        #expect(
            questions.allSatisfy { $0.options.contains($0.correctAnswer) },
            "a correct answer that isn't one of the options can never be picked"
        )
    }
}
