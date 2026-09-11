//
//  WordGuessEvaluation.swift
//  Twofold
//
//  Scoring one guess against the answer.
//
//  Pure, and in its own file, because this is the rule everybody gets wrong. The naive version —
//  "green if it matches here, yellow if the answer contains it anywhere" — is right for words with
//  no repeated letters, which is most of them, so it passes every casual test and then lies.
//
//  Guess CRANE against ERASE: the first E is not in the answer's first-E position, and the answer
//  has only one E, which the final E has already claimed as green. So the leading E must come back
//  grey, not yellow. A yellow there says "there is another E somewhere else" — a statement about
//  the answer that is false, and one the player will act on.
//
//  The rule that gets it right: greens are assigned first and consume their letter, then yellows
//  are handed out from whatever letters are left over, in order. A letter can only be marked as
//  many times as it actually occurs.
//

import Foundation

/// What one tile says about one letter.
enum WordGuessMark: String, Codable, Hashable {
    /// Right letter, right place.
    case correct
    /// The answer contains this letter, but not here — and there is one spare to account for it.
    case present
    /// Not in the answer, or every copy of it is already spoken for by a greener tile.
    case absent
}

enum WordGuessEvaluation {

    /// One mark per letter of `guess`, scored against `answer`.
    ///
    /// Both are expected to be the same length and already lowercased; a mismatch returns an empty
    /// array rather than guessing at intent, since every caller builds both from the same source.
    static func marks(guess: String, answer: String) -> [WordGuessMark] {
        let guessLetters = Array(guess.lowercased())
        let answerLetters = Array(answer.lowercased())
        guard guessLetters.count == answerLetters.count else { return [] }

        var marks = [WordGuessMark](repeating: .absent, count: guessLetters.count)

        // How many of each letter the answer has left to give out. Greens take theirs first, below,
        // which is the whole of what makes a repeated letter come out right.
        var remaining: [Character: Int] = [:]
        for letter in answerLetters { remaining[letter, default: 0] += 1 }

        for index in guessLetters.indices where guessLetters[index] == answerLetters[index] {
            marks[index] = .correct
            remaining[guessLetters[index]]! -= 1
        }

        for index in guessLetters.indices where marks[index] != .correct {
            let letter = guessLetters[index]
            if let left = remaining[letter], left > 0 {
                marks[index] = .present
                remaining[letter] = left - 1
            }
        }

        return marks
    }

    /// What the keyboard should show for each letter, given everything guessed so far.
    ///
    /// A letter keeps the best news it has ever had: once a G has come back green, a later guess
    /// putting it in the wrong place must not demote the key to yellow. The player would read that
    /// as the answer having changed.
    static func keyboardMarks(guesses: [String], answer: String) -> [Character: WordGuessMark] {
        var best: [Character: WordGuessMark] = [:]
        let rank: [WordGuessMark: Int] = [.absent: 0, .present: 1, .correct: 2]

        for guess in guesses {
            let marks = marks(guess: guess, answer: answer)
            for (letter, mark) in zip(Array(guess.lowercased()), marks) {
                if let existing = best[letter], rank[existing]! >= rank[mark]! { continue }
                best[letter] = mark
            }
        }
        return best
    }
}
