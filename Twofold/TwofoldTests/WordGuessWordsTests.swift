//
//  WordGuessWordsTests.swift
//  TwofoldTests
//
//  The word lists, and the contract that the answer list's *order* is part of the wire format.
//
//  A word is chosen by indexing `answers` with the puzzle's id, so inserting a word in the middle
//  silently changes the answer of every board currently in play — and two partners on different app
//  versions would be solving different words while comparing scores. The count and checksum below
//  exist to turn that from a silent content edit into a failing test.
//
//  If these fail because words were deliberately added: append them to the END of
//  word-guess-answers.txt, never insert or re-sort, then update the numbers here.
//

import Foundation
import Testing
@testable import Twofold

struct WordGuessWordsTests {

    // MARK: - The lists load at all

    @Test func bothListsAreBundled() {
        // A missing resource means every board in the app is unplayable, and the failure mode is
        // silent — `answer(for:)` returns nil and the screen shows an error nobody can act on.
        #expect(!WordGuessWords.answers.isEmpty)
        #expect(!WordGuessWords.allowedGuesses.isEmpty)
    }

    @Test func everyWordIsFiveLowercaseLetters() {
        let badAnswers = WordGuessWords.answers.filter { word in
            word.count != 5 || word.contains { !$0.isLowercase || !$0.isLetter }
        }
        #expect(badAnswers.isEmpty, "answers must be five lowercase letters: \(badAnswers.prefix(10))")

        let badGuesses = WordGuessWords.allowedGuesses.filter { word in
            word.count != 5 || word.contains { !$0.isLowercase || !$0.isLetter }
        }
        #expect(badGuesses.isEmpty, "guesses must be five lowercase letters: \(badGuesses.prefix(10))")
    }

    @Test func everyAnswerIsAlsoALegalGuess() {
        // Otherwise the game refuses its own solution: a player types the right word and is told it
        // is not in the word list.
        let orphans = WordGuessWords.answers.filter { !WordGuessWords.isAllowed($0) }
        #expect(orphans.isEmpty, "answers the board would reject: \(orphans.prefix(10))")
    }

    @Test func thereAreNoDuplicateAnswers() {
        #expect(Set(WordGuessWords.answers).count == WordGuessWords.answers.count)
    }

    // MARK: - The compatibility contract

    @Test func theAnswerListHasNotMoved() {
        // Both halves matter. The count catches an append; the checksum catches an insert or a
        // re-sort, which is the change that would quietly repoint every in-flight board.
        #expect(WordGuessWords.answers.count == 1599)

        var hash: UInt64 = 5381
        for character in WordGuessWords.answers.joined(separator: ",").unicodeScalars {
            hash = (hash &* 33) &+ UInt64(character.value)
        }
        #expect(hash == WordGuessWordsTests.pinnedAnswerHash, "the answer list changed order or content")
    }

    /// Recomputed only when the list is deliberately extended — and only ever by appending.
    private static let pinnedAnswerHash: UInt64 = 17_268_810_451_098_326_010

    // MARK: - Deriving the word

    @Test func thesamePuzzleIdAlwaysGivesTheSameWord() {
        // The entire reason two partners can play the same board without the server knowing the
        // word. If this stops being true they silently play different words.
        let id = UUID(uuidString: "7F3C1A2B-4D5E-6F70-8192-A3B4C5D6E7F8")!
        let first = WordGuessWords.answer(for: id)
        #expect(first != nil)
        #expect(first == WordGuessWords.answer(for: id))
        #expect(first == WordGuessWords.answer(for: id))
    }

    @Test func differentPuzzleIdsSpreadAcrossTheList() {
        // Not a distribution test — just enough to catch a derivation that collapses to one word,
        // which would otherwise look fine until somebody noticed the same answer every day.
        let words = Set((0..<200).map { _ in WordGuessWords.answer(for: UUID()) ?? "" })
        #expect(words.count > 100, "200 puzzles produced only \(words.count) distinct words")
    }

    // MARK: - What the board accepts

    @Test func realWordsAreAccepted() {
        // Plurals and modern words, which the system dictionary this list was built from does not
        // carry. Being told a word you know is real is not in the list is the worst moment this
        // game has, so these are pinned rather than trusted.
        for word in ["tacos", "email", "walks", "liked", "blogs", "vegan", "scuba", "pizza", "books", "fries"] {
            #expect(WordGuessWords.isAllowed(word), "\(word) should be a legal guess")
        }
    }

    @Test func bothSpellingsAreAccepted() {
        // Answers are American; guesses are not. Somebody who writes British or Australian English
        // should never be told their own spelling is not a word.
        for pair in [("meter", "metre"), ("liter", "litre"), ("fiber", "fibre"), ("tires", "tyres")] {
            #expect(WordGuessWords.isAllowed(pair.0), "\(pair.0) should be a legal guess")
            #expect(WordGuessWords.isAllowed(pair.1), "\(pair.1) should be a legal guess")
        }
    }

    @Test func nonsenseIsRejected() {
        for word in ["zzzzz", "qwert", "aaaaa"] {
            #expect(!WordGuessWords.isAllowed(word), "\(word) should not be a legal guess")
        }
    }

    @Test func caseAndLengthAreHandled() {
        #expect(WordGuessWords.isAllowed("CRANE"))
        #expect(!WordGuessWords.isAllowed("four"))
        #expect(!WordGuessWords.isAllowed(""))
    }
}
