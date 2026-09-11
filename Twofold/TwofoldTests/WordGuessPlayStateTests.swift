//
//  WordGuessPlayStateTests.swift
//  TwofoldTests
//
//  The board's rules, its wire format, and the comparison that reads it back.
//
//  The thread running through all of it: a board can finish *without* being solved, and six guesses
//  and a miss is not the same result as six guesses and a win. Every layer has to keep those apart,
//  and each one of them would look fine in a screenshot of a board that was solved.
//

import Foundation
import Testing
@testable import Twofold

struct WordGuessPlayStateTests {

    // MARK: - Committing guesses

    @Test func aRealWordIsAccepted() {
        var state = WordGuessPlayState(answer: "roast")
        #expect(state.commit("crane") == nil)
        #expect(state.guesses == ["crane"])
    }

    @Test func aShortGuessIsRefusedForBeingShort() {
        var state = WordGuessPlayState(answer: "roast")
        #expect(state.commit("cran") == .wrongLength)
        #expect(state.guesses.isEmpty)
    }

    @Test func nonsenseIsRefusedForNotBeingAWord() {
        var state = WordGuessPlayState(answer: "roast")
        #expect(state.commit("zzzzz") == .notAWord)
        #expect(state.guesses.isEmpty)
    }

    @Test func aRepeatedGuessIsRefusedRatherThanWastingATurn() {
        // Retyping a word you have already had back is a mis-tap or a forgotten row, never a
        // strategy — spending one of six guesses on it punishes the player for the board being
        // hard to read.
        var state = WordGuessPlayState(answer: "roast")
        _ = state.commit("crane")
        #expect(state.commit("crane") == .alreadyGuessed)
        #expect(state.guesses.count == 1)
    }

    @Test func caseIsNormalisedOnTheWayIn() {
        var state = WordGuessPlayState(answer: "roast")
        #expect(state.commit("CRANE") == nil)
        #expect(state.guesses == ["crane"])
    }

    // MARK: - Finishing

    @Test func gettingTheWordEndsTheBoard() {
        var state = WordGuessPlayState(answer: "roast")
        _ = state.commit("crane")
        _ = state.commit("roast")
        #expect(state.isSolved)
        #expect(state.isComplete)
        #expect(!state.isFailed)
        #expect(state.guessesUsed == 2)
        #expect(!state.canGuessAgain)
    }

    @Test func sixWrongGuessesAlsoEndsTheBoard() throws {
        var state = WordGuessPlayState(answer: "roast")
        for word in ["crane", "blimp", "sushi", "vodka", "fudge", "tempo"] {
            #expect(state.commit(word) == nil, "\(word) should have been accepted")
        }
        #expect(state.isFailed)
        #expect(state.isComplete)
        #expect(!state.isSolved)
        // Not "used 6" — they never got there, and a guess count with no win beside it is the
        // number that gets mistaken for a score.
        #expect(state.guessesUsed == nil)
    }

    @Test func aFinishedBoardTakesNoMoreGuesses() {
        var state = WordGuessPlayState(answer: "roast")
        _ = state.commit("roast")
        #expect(state.commit("crane") == .boardFinished)
        #expect(state.guesses.count == 1)
    }

    // MARK: - The wire format

    @Test func aBoardSurvivesARoundTrip() throws {
        var state = WordGuessPlayState(answer: "roast")
        _ = state.commit("crane")
        _ = state.commit("toads")
        state.elapsed = 97

        let restored = try #require(WordGuessPlayState.decoded(from: state.encoded, answer: "roast"))
        #expect(restored.guesses == ["crane", "toads"])
        #expect(restored.elapsed == 97)
        #expect(restored.answer == "roast")
        #expect(!restored.isComplete)
    }

    @Test func anEmptyBoardRoundTrips() throws {
        // The empty guesses field splits to [""] rather than [], which is exactly the kind of thing
        // that turns "no guesses yet" into a decode failure and starts somebody's board over.
        let state = WordGuessPlayState(answer: "roast")
        let restored = try #require(WordGuessPlayState.decoded(from: state.encoded, answer: "roast"))
        #expect(restored.guesses.isEmpty)
    }

    @Test func theAnswerIsNeverWrittenIntoThePayload() {
        // Both partners can read the row this string lands in. If the word is in it, either of them
        // can read the answer out of it.
        var state = WordGuessPlayState(answer: "roast")
        _ = state.commit("crane")
        #expect(!state.encoded.contains("roast"))
    }

    @Test func aPayloadThisBuildCannotReadIsRefusedRatherThanRepaired() {
        // A board restored wrong is worse than one restored not at all, because the player cannot
        // tell which they are looking at.
        #expect(WordGuessPlayState.decoded(from: "", answer: "roast") == nil)
        #expect(WordGuessPlayState.decoded(from: "wordguess.v2|crane|10|0", answer: "roast") == nil)
        #expect(WordGuessPlayState.decoded(from: "wordguess.v1|crane|10", answer: "roast") == nil)
        #expect(WordGuessPlayState.decoded(from: "wordguess.v1|crane|-5|0", answer: "roast") == nil)
        // A guess of the wrong length, or more guesses than the board has rows.
        #expect(WordGuessPlayState.decoded(from: "wordguess.v1|cran|10|0", answer: "roast") == nil)
        #expect(WordGuessPlayState.decoded(
            from: "wordguess.v1|crane,blimp,sushi,vodka,fudge,tempo,roast|10|1", answer: "roast"
        ) == nil)
        // Duplicates cannot happen on a real board, so a payload carrying them was written against
        // a different puzzle or by a build whose rules differed.
        #expect(WordGuessPlayState.decoded(from: "wordguess.v1|crane,crane|10|0", answer: "roast") == nil)
    }

    @Test func theSummaryReadsAResultWithoutKnowingTheWord() throws {
        // The comparison and the stats hold the string but not the word it was played against —
        // deriving the puzzle again just to read two fields would be the expensive way to be wrong.
        var won = WordGuessPlayState(answer: "roast")
        _ = won.commit("crane")
        _ = won.commit("roast")
        won.elapsed = 44

        let summary = try #require(WordGuessPlayState.summary(from: won.encoded))
        #expect(summary.guessCount == 2)
        #expect(summary.solved)
        #expect(summary.elapsed == 44)
    }

    @Test func theSummaryTellsAMissFromAWin() throws {
        var missed = WordGuessPlayState(answer: "roast")
        for word in ["crane", "blimp", "sushi", "vodka", "fudge", "tempo"] { _ = missed.commit(word) }

        let summary = try #require(WordGuessPlayState.summary(from: missed.encoded))
        #expect(summary.guessCount == 6)
        #expect(!summary.solved)
    }

    @Test func theSummaryIsAsStrictAsTheFullDecoder() {
        // Pinned to each other: a payload one accepts and the other refuses is a row that reads one
        // way in the comparison and another on the board.
        for payload in ["", "wordguess.v2|crane|10|0", "wordguess.v1|crane|10", "wordguess.v1|cran|10|0"] {
            #expect(WordGuessPlayState.summary(from: payload) == nil, "\(payload) should be refused")
            #expect(WordGuessPlayState.decoded(from: payload, answer: "roast") == nil, "\(payload) should be refused")
        }
    }
}

struct WordGuessComparisonTests {

    private func summary(_ count: Int, solved: Bool, elapsed: TimeInterval = 60) -> WordGuessSummary {
        WordGuessSummary(guessCount: count, solved: solved, elapsed: elapsed)
    }

    @Test func fewerGuessesWins() {
        let comparison = WordGuessComparison(
            mine: summary(3, solved: true), theirs: summary(5, solved: true), partnerName: "Erin"
        )
        #expect(comparison.outcome == .me)
        #expect(comparison.margin == 2)
    }

    @Test func gettingItBeatsNotGettingIt() {
        // The case the whole file exists for. On guess count alone this is a dead heat, and it is
        // the one verdict neither of them would accept.
        let comparison = WordGuessComparison(
            mine: summary(6, solved: true), theirs: summary(6, solved: false), partnerName: "Erin"
        )
        #expect(comparison.outcome == .me)
        #expect(comparison.verdict.resolved.contains("You got it"))
    }

    @Test func aWinInSixBeatsAMissInThree() {
        // A miss cannot have fewer than six guesses on a real board, but the type allows it and the
        // rule should not depend on that.
        let comparison = WordGuessComparison(
            mine: summary(6, solved: true), theirs: summary(3, solved: false), partnerName: "Erin"
        )
        #expect(comparison.outcome == .me)
    }

    @Test func twoMissesAreATieRatherThanARanking() {
        // Ranking two failures by how many guesses they spent getting nowhere would be inventing a
        // winner out of nothing.
        let comparison = WordGuessComparison(
            mine: summary(6, solved: false), theirs: summary(4, solved: false), partnerName: "Erin"
        )
        #expect(comparison.outcome == .tie)
        #expect(comparison.margin == 0)
        #expect(comparison.verdict.resolved == "Neither of you got it this time.")
    }

    @Test func equalCountsAreADeadHeat() {
        let comparison = WordGuessComparison(
            mine: summary(4, solved: true), theirs: summary(4, solved: true), partnerName: "Erin"
        )
        #expect(comparison.outcome == .tie)
        #expect(comparison.verdict.resolved.contains("dead heat"))
    }

    @Test func timeNeverDecidesIt() {
        // Deduction, not speed. Making it a race would reward guessing fast over guessing well.
        let slowWinner = WordGuessComparison(
            mine: summary(3, solved: true, elapsed: 900),
            theirs: summary(4, solved: true, elapsed: 30),
            partnerName: "Erin"
        )
        #expect(slowWinner.outcome == .me)
    }

    @Test func theSharedVerdictNamesBothSides() {
        // "You" means the sender to everybody looking at a shared card — including the partner, who
        // would read someone else's win as their own.
        let comparison = WordGuessComparison(
            mine: summary(3, solved: true), theirs: summary(5, solved: true), partnerName: "Erin"
        )
        let shared = comparison.sharedVerdict(myName: "Alex").resolved
        #expect(shared.contains("Alex"))
        #expect(!shared.contains("You"))
    }

    @Test func theScoreReadsAsAScoreOrAMiss() {
        #expect(WordGuessComparison.scoreText(summary(3, solved: true)).resolved == "3/6")
        #expect(WordGuessComparison.scoreText(summary(6, solved: false)).resolved == "Missed")
    }

    @Test func oneGuessIsSingular() {
        #expect(WordGuessComparison.guessText(1) == "1 guess")
        #expect(WordGuessComparison.guessText(4) == "4 guesses")
    }
}
