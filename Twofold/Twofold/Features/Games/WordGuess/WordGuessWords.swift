//
//  WordGuessWords.swift
//  Twofold
//
//  The two word lists, and how a puzzle's identity becomes a word.
//
//  ---------------------------------------------------------------------------
//  Why there are two lists and not one
//  ---------------------------------------------------------------------------
//
//  One list cannot do both jobs. The answers have to be words people actually know, or the game is
//  unwinnable and feels arbitrary. The accepted guesses have to be far wider than that, or the game
//  rejects real words somebody has just typed — which is the single most irritating thing this kind
//  of game can do, because it reads as the app calling you wrong.
//
//  So: ~1,600 common words that can be the answer, and ~20,000 that are merely allowed.
//
//  ---------------------------------------------------------------------------
//  Spelling
//  ---------------------------------------------------------------------------
//
//  Answers are American. Not a judgement about English — a five-letter grid can only hold one
//  spelling, and if both were possible then somebody spelling it their own way would be told they
//  were wrong. Most of the famous pairs settle themselves (`colour`, `honour` and `favour` are six
//  letters, so they cannot be typed at all); it only really bites on `meter`/`metre`,
//  `liter`/`litre`, `fiber`/`fibre` and `tires`/`tyres`.
//
//  The guess list accepts both, deliberately. Costs nothing, and spares anyone who does not write
//  American English the experience of typing a word they know is real and being told it is not.
//
//  ---------------------------------------------------------------------------
//  The compatibility contract
//  ---------------------------------------------------------------------------
//
//  A word is chosen by indexing `answers` with the puzzle's id. That means the answer list's
//  *order* is part of the wire format: inserting a word in the middle silently changes the answer
//  of every in-flight puzzle, and two partners on different app versions would then be solving
//  different words while comparing scores.
//
//  `WordGuessWordsTests` pins the list's count and a checksum for exactly that reason. If those
//  fail, the change is a compatibility break rather than a content edit — the safe way to add words
//  is to append them to the end of the file, never to insert or reorder.
//

import Foundation

enum WordGuessWords {
    static let length = 5
    /// Six rows on the board. Enough that a bad start is recoverable, few enough that it is a game.
    static let maxGuesses = 6

    /// Words that can be the answer. Loaded once, kept for the process's life — it is 10KB.
    static let answers: [String] = load("word-guess-answers")

    /// Every word the board will accept, the answers included. A set because this is only ever
    /// asked "is this in you?", 20,000 times less often than it would be asked as an array.
    static let allowedGuesses: Set<String> = Set(load("word-guess-guesses"))

    /// The answer for a puzzle, derived rather than stored.
    ///
    /// Both partners read the same `content_id` off the same round and land on the same word
    /// without the server ever knowing it — which is the point. The word cannot be stored on the
    /// session row, because both partners can read that row, and one of them reading the answer out
    /// of it is not a hypothetical.
    ///
    /// Returns nil only if the bundled list is missing, which is a broken build rather than a state
    /// to handle — the caller shows the failed phase rather than inventing a word.
    static func answer(for puzzleID: UUID) -> String? {
        guard !answers.isEmpty else { return nil }
        var random = PuzzleRandom(puzzleID: puzzleID)
        return answers[random.next(upperBound: answers.count)]
    }

    /// Whether the board should accept this as a guess.
    ///
    /// Length is checked separately by the caller so it can say "not enough letters" rather than
    /// "not a word" — two different mistakes that deserve two different messages.
    static func isAllowed(_ word: String) -> Bool {
        allowedGuesses.contains(word.lowercased())
    }

    private static func load(_ resource: String) -> [String] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { $0.count == length }
    }
}
