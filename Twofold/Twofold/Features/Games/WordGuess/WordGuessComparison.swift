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

    var verdict: String {
        switch (mine.solved, theirs.solved) {
        case (false, false):
            return "Neither of you got it this time."
        case (true, false):
            return "You got it in \(Self.guessText(mine.guessCount)). \(partnerName) didn't."
        case (false, true):
            return "\(partnerName) got it in \(Self.guessText(theirs.guessCount)). You'll get the next one."
        case (true, true):
            if margin == 0 {
                return "A dead heat — \(Self.guessText(mine.guessCount)) each."
            }
            let leader = outcome == .me ? "You" : partnerName
            let count = outcome == .me ? mine.guessCount : theirs.guessCount
            return "\(leader) got there in \(Self.guessText(count)), \(margin) fewer."
        }
    }

    /// The same verdict for a card that leaves the device, where "you" names the sender to everyone
    /// looking at it — including the partner, who would otherwise read someone else's win as theirs.
    func sharedVerdict(myName: String) -> String {
        switch (mine.solved, theirs.solved) {
        case (false, false):
            return "Neither of them got it this time."
        case (true, false):
            return "\(myName) got it in \(Self.guessText(mine.guessCount)); \(partnerName) didn't."
        case (false, true):
            return "\(partnerName) got it in \(Self.guessText(theirs.guessCount)); \(myName) didn't."
        case (true, true):
            if margin == 0 {
                return "A dead heat — \(Self.guessText(mine.guessCount)) each."
            }
            let leader = outcome == .me ? myName : partnerName
            let count = outcome == .me ? mine.guessCount : theirs.guessCount
            return "\(leader) got there in \(Self.guessText(count)), \(margin) fewer."
        }
    }

    /// "1 guess" / "4 guesses". Singular matters here because one guess is the result people
    /// actually talk about.
    static func guessText(_ count: Int) -> String {
        count == 1 ? "1 guess" : "\(count) guesses"
    }

    /// What a single board scored, for a row that shows one side. "X/6", the way this kind of
    /// result has always been written, with a miss as "X/6" struck through by the word "missed"
    /// rather than a number nobody can read as a failure.
    static func scoreText(_ summary: WordGuessSummary) -> String {
        summary.solved ? "\(summary.guessCount)/\(WordGuessWords.maxGuesses)" : "Missed"
    }
}
