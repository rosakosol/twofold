//
//  UnknownGameTypeTests.swift
//  TwofoldTests
//
//  CORE-8. A game type added on the server broke deck and history loading on every older app:
//  one row with an unknown `game_type` failed the whole array.
//

import Foundation
import Testing
@testable import Twofold

struct UnknownGameTypeTests {

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test("a deck of a game this build does not know is skipped, not fatal")
    func unknownDeckSkipped() throws {
        let json = """
        [
          {"id":"5A1E6C7E-0000-0000-0000-000000000001","topic":"t","game_type":"future_game","title":"New","emoji":"✨","tier":"plus","sort_order":0,"question_count":10},
          {"id":"5A1E6C7E-0000-0000-0000-000000000002","topic":"t","game_type":"trivia_battle","title":"Trivia","emoji":"🧠","tier":"plus","sort_order":1,"question_count":10}
        ]
        """
        let rows = try decoder().decode(BackendService.KnownGameTypes<BackendService.GameDeckRow>.self, from: Data(json.utf8))
        #expect(rows.elements.map(\.title) == ["Trivia"])
    }

    @Test("an open game of an unknown type is skipped")
    func unknownOpenGameSkipped() throws {
        let json = """
        [
          {"session_id":"5A1E6C7E-0000-0000-0000-000000000003","game_type":"future_game","label":null,"is_my_turn":true,"updated_at":"2026-11-01T10:00:00Z"},
          {"session_id":"5A1E6C7E-0000-0000-0000-000000000004","game_type":"sudoku","label":"easy","is_my_turn":false,"updated_at":"2026-11-01T10:00:00Z"}
        ]
        """
        let games = try decoder().decode(BackendService.KnownGameTypes<BackendService.OpenGame>.self, from: Data(json.utf8))
        #expect(games.elements.map(\.gameType) == [.sudoku])
    }

    /// Only an unknown game type is forgiven. A row that is broken some other way still fails, so
    /// a real schema mistake is not hidden behind an empty list.
    @Test("a known game type with a broken row still fails loudly")
    func brokenKnownRowStillThrows() {
        let json = """
        [{"id":"5A1E6C7E-0000-0000-0000-000000000005","topic":"t","game_type":"trivia_battle","title":"Trivia"}]
        """
        #expect(throws: (any Error).self) {
            try decoder().decode(BackendService.KnownGameTypes<BackendService.GameDeckRow>.self, from: Data(json.utf8))
        }
    }
}
