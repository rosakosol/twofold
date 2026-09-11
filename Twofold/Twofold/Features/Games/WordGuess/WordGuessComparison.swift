//
//  WordGuessComparison.swift
//  Twofold
//
//  Two finished boards and what to say about them.
//
//  Separate from the view for the same reason `SudokuComparison` is: the rules here are the kind
//  that go wrong quietly. Sudoku compares one number, and this compares two that disagree — the
//  guesses used and whether the word was got at all — with the second overriding the first.
//
//  The case that makes it worth a file: somebody who missed in six and somebody who got it in six
//  have the same guess count and did not do the same thing. Comparing on count alone calls that a
//  dead heat, which is the one verdict neither of them would accept.
//

import Foundation

struct WordGuessComparison: Equatable {
    enum Outcome: Equatable {
        case me
        case partner
        case tie
    }

    let mine: WordGuessSummary
    let theirs: WordGuessSummary
    let partnerName: String

    /// Getting the word beats not getting it, whatever the counts say. Below that, fewer guesses
    /// wins. Time is deliberately not part of it — this is a puzzle about deduction, and making it
    /// a race would reward guessing fast over guessing well.
    var outcome: Outcome {
        if mine.solved != theirs.solved { return mine.solved ? .me : .partner }
        // Neither of them got it. There is no winner in that, and ranking two failures by how many
        // guesses they spent getting nowhere would be inventing one.
        guard mine.solved else { return .tie }
        if mine.guessCount < theirs.guessCount { return .me }
        if mine.guessCount > theirs.guessCount { return .partner }
        return .tie
    }

    /// How many guesses apart, when both solved it. Zero otherwise — there is no meaningful gap
    /// between a win and a miss, and `verdict` never asks for one.
    var margin: Int {
        guard mine.solved, theirs.solved else { return 0 }
        return abs(mine.guessCount - theirs.guessCount)
    }

    /// `LocalizedStringResource`, not `String` — see `SudokuComparison.verdict` for why a sentence
    /// returned as a plain `String` is invisible both to `Text`'s localisation and to Xcode's
    /// string extractor.
    var verdict: LocalizedStringResource {
        switch (mine.solved, theirs.solved) {
        case (false, false):
            return LocalizedStringResource(
                "Neither of you got it this time.",
                comment: "Word Guess comparison when both players ran out of guesses."
            )
        case (true, false):
            return LocalizedStringResource(
                "You got it in \(Self.guessText(mine.guessCount)). \(partnerName) didn't.",
                comment: "Word Guess comparison, only this player solved it. First value is a guess count like \u{201C}3 guesses\u{201D}, second is the partner's name."
            )
        case (false, true):
            return LocalizedStringResource(
                "\(partnerName) got it in \(Self.guessText(theirs.guessCount)). You'll get the next one.",
                comment: "Word Guess comparison, only the partner solved it. First value is their name, second is a guess count."
            )
        case (true, true):
            if margin == 0 {
                return LocalizedStringResource(
                    "A dead heat — \(Self.guessText(mine.guessCount)) each.",
                    comment: "Word Guess comparison, both solved it in the same number of guesses. The value is a guess count."
                )
            }
            let leader = outcome == .me ? String(localized: "You") : partnerName
            let count = outcome == .me ? mine.guessCount : theirs.guessCount
            return LocalizedStringResource(
                "\(leader) got there in \(Self.guessText(count)), \(margin) fewer.",
                comment: "Word Guess comparison, both solved it. Values are: the winner's name or \u{201C}You\u{201D}, a guess count, and how many fewer guesses they used."
            )
        }
    }

    /// The same verdict for a card that leaves the device, where "you" names the sender to everyone
    /// looking at it — including the partner, who would otherwise read someone else's win as theirs.
    func sharedVerdict(myName: String) -> LocalizedStringResource {
        switch (mine.solved, theirs.solved) {
        case (false, false):
            return LocalizedStringResource(
                "Neither of them got it this time.",
                comment: "Shareable Word Guess card, neither player solved it."
            )
        case (true, false):
            return LocalizedStringResource(
                "\(myName) got it in \(Self.guessText(mine.guessCount)); \(partnerName) didn't.",
                comment: "Shareable Word Guess card, only the sender solved it. Values are: sender's name, a guess count, the partner's name."
            )
        case (false, true):
            return LocalizedStringResource(
                "\(partnerName) got it in \(Self.guessText(theirs.guessCount)); \(myName) didn't.",
                comment: "Shareable Word Guess card, only the partner solved it. Values are: partner's name, a guess count, the sender's name."
            )
        case (true, true):
            if margin == 0 {
                return LocalizedStringResource(
                    "A dead heat — \(Self.guessText(mine.guessCount)) each.",
                    comment: "Shareable Word Guess card, both solved it in the same number of guesses."
                )
            }
            let leader = outcome == .me ? myName : partnerName
            let count = outcome == .me ? mine.guessCount : theirs.guessCount
            return LocalizedStringResource(
                "\(leader) got there in \(Self.guessText(count)), \(margin) fewer.",
                comment: "Shareable Word Guess card, both solved it. Values are: the winner's name, a guess count, and how many fewer guesses."
            )
        }
    }

    /// "1 guess" / "4 guesses", through a plural key in the String Catalog rather than a ternary.
    ///
    /// The ternary it replaces encoded an assumption — that a language has exactly two plural forms
    /// and switches at one — which is true of English and not of Polish, Russian or Arabic. Only
    /// the catalog can hold that rule per language.
    ///
    /// Resolved to a `String` here because it is interpolated into the sentences above. Fully
    /// correct would be one key per sentence, inflected on the count itself; that needs a
    /// translator's judgement per language and is worth doing when there is one to ask.
    static func guessText(_ count: Int) -> String {
        String(localized: "\(count) guesses")
    }

    /// What a single board scored, for a row that shows one side. "X/6", the way this kind of
    /// result has always been written, with a miss as "X/6" struck through by the word "missed"
    /// rather than a number nobody can read as a failure.
    static func scoreText(_ summary: WordGuessSummary) -> LocalizedStringResource {
        summary.solved
            ? LocalizedStringResource(
                "\(summary.guessCount)/\(WordGuessWords.maxGuesses)",
                comment: "Word Guess score: guesses used out of the six available."
            )
            : LocalizedStringResource(
                "Missed",
                comment: "Word Guess score when the player never got the word. Sits where a score like \u{201C}3/6\u{201D} otherwise goes, so it wants to be about as short."
            )
    }
}
