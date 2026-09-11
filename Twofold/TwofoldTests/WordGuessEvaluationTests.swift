//
//  WordGuessEvaluationTests.swift
//  TwofoldTests
//
//  The repeated-letter cases, which are the only ones worth writing down. A guess whose letters are
//  all distinct scores correctly under any implementation, including a wrong one.
//

import Testing
@testable import Twofold

struct WordGuessEvaluationTests {

    private func marks(_ guess: String, _ answer: String) -> String {
        WordGuessEvaluation.marks(guess: guess, answer: answer).map {
            switch $0 {
            case .correct: "G"
            case .present: "Y"
            case .absent: "-"
            }
        }.joined()
    }

    @Test func everyLetterInPlace() {
        #expect(marks("crane", "crane") == "GGGGG")
    }

    @Test func nothingInCommon() {
        #expect(marks("crumb", "split") == "-----")
    }

    @Test func aLetterInTheWrongPlaceIsPresent() {
        //   guess  C R A N E
        //   answer R O A S T
        // A is in place. R is in the answer but not first. C, N and E are not in it at all.
        #expect(marks("crane", "roast") == "-YG--")
    }

    @Test func aSecondCopyOfALetterTheAnswerOnlyHasOnceComesBackGrey() {
        //   guess  E E R I E
        //   answer E R A S E
        // The answer has exactly two E's, and the guess's first and last take both as green. The
        // middle E has nothing left to claim, so it is grey — a yellow there would tell the player
        // there is a third E somewhere, which is a lie they would then act on.
        #expect(marks("eerie", "erase") == "G-Y-G")
    }

    @Test func greensClaimTheirLetterBeforeYellowsAreHandedOut() {
        // SPEED against ABIDE: one E in the answer, at index 4. Neither of SPEED's E's is there, so
        // exactly one of them may be yellow — the first, in order — and the second must be grey.
        // D is present (answer has D at index 3, guess has it at 4).
        #expect(marks("speed", "abide") == "--Y-Y")
    }

    @Test func aRepeatedLetterCanBeGreenAndYellowAtOnce() {
        // GEESE against SEEDS: answer S E E D S.
        //   G-> not S, E at 1 == E green, E at 2 == E green, S at 3 vs D -> answer has S spare
        //   (two S, none claimed) -> present. E at 4 vs S -> both E already spent -> grey.
        #expect(marks("geese", "seeds") == "-GGY-")
    }

    @Test func mismatchedLengthsScoreNothingRatherThanGuessing() {
        #expect(WordGuessEvaluation.marks(guess: "four", answer: "fives").isEmpty)
    }

    @Test func caseDoesNotMatter() {
        // The board holds uppercase and the word lists are lowercase, so this conversion happens on
        // every single guess.
        #expect(marks("CRANE", "crane") == "GGGGG")
        #expect(marks("crane", "CRANE") == "GGGGG")
    }

    // MARK: - Keyboard

    @Test func theKeyboardKeepsTheBestNewsALetterHasHad() {
        // R comes back green in the first guess and yellow in the second. The key must stay green:
        // demoting it would read as the answer having moved.
        let best = WordGuessEvaluation.keyboardMarks(guesses: ["roast", "brick"], answer: "roast")
        #expect(best["r"] == .correct)
    }

    @Test func theKeyboardPromotesGreyToYellowToGreen() {
        let afterGrey = WordGuessEvaluation.keyboardMarks(guesses: ["blimp"], answer: "roast")
        #expect(afterGrey["b"] == .absent)

        let afterYellow = WordGuessEvaluation.keyboardMarks(guesses: ["blimp", "sappy"], answer: "roast")
        #expect(afterYellow["s"] == .present)

        let afterGreen = WordGuessEvaluation.keyboardMarks(guesses: ["blimp", "sappy", "roast"], answer: "roast")
        #expect(afterGreen["s"] == .correct)
    }

    @Test func anUnguessedLetterHasNoMark() {
        let best = WordGuessEvaluation.keyboardMarks(guesses: ["roast"], answer: "roast")
        #expect(best["z"] == nil)
    }
}
