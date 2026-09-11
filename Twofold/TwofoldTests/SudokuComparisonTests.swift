//
//  SudokuComparisonTests.swift
//  TwofoldTests
//
//  The comparison is the only place a sudoku session says anything about the two players relative
//  to each other, and every way it can be wrong is a way that looks fine:
//
//    * Two times that read identically on screen producing a winner, and a "0s ahead" verdict to
//      justify it. The player can see both clocks say 2:14; nothing on the screen explains the
//      result, because the reason is a fractional second neither clock ever showed.
//    * A margin phrased in raw seconds once it passes a minute — "187s ahead".
//    * The verdict naming the wrong person, which only shows up when the partner is the faster one.
//

import Testing
import Foundation
@testable import Twofold

struct SudokuComparisonTests {
    private func comparison(mine: TimeInterval, theirs: TimeInterval) -> SudokuComparison {
        SudokuComparison(myElapsed: mine, partnerElapsed: theirs, partnerName: "Erin")
    }

    // MARK: - Who was faster

    @Test("the quicker time wins, from either side")
    func outcomes() {
        #expect(comparison(mine: 134, theirs: 182).outcome == .me)
        #expect(comparison(mine: 604, theirs: 417).outcome == .partner)
        #expect(comparison(mine: 240, theirs: 240).outcome == .tie)
    }

    @Test("the margin is the gap between them, signed towards whoever was quicker")
    func margins() {
        #expect(comparison(mine: 134, theirs: 182).margin == 48)
        #expect(comparison(mine: 604, theirs: 417).margin == -187)
        #expect(comparison(mine: 240, theirs: 240).margin == 0)
    }

    /// The clocks only ever showed whole seconds. Two solves a third of a second apart both read
    /// 2:14, so calling one of them the winner is a result the player cannot see the reason for.
    @Test("times that read the same on screen are a dead heat, not a photo finish")
    func subSecondDifferencesAreATie() {
        #expect(comparison(mine: 134.2, theirs: 134.4).outcome == .tie)
        #expect(comparison(mine: 134.2, theirs: 134.4).margin == 0)
        #expect(comparison(mine: 134.0, theirs: 134.49).verdict.contains("dead heat"))
    }

    /// A stopwatch counts completed seconds, so 134.6 displays as 2:14. The margin has to be built
    /// from that same truncation: against a partner's 2:20 the honest gap is 6s, where rounding to
    /// 135 would announce 5s underneath two rows that plainly differ by six.
    @Test("the margin is the gap between the times as displayed, not as stored")
    func marginAgreesWithTheDisplayedRows() {
        let close = comparison(mine: 134.6, theirs: 140.0)
        #expect(SudokuComparison.clockText(close.myElapsed) == "2:14")
        #expect(SudokuComparison.clockText(close.partnerElapsed) == "2:20")
        #expect(close.margin == 6)
        #expect(close.verdict == "You finished 6s ahead.")
    }

    // MARK: - How it reads

    @Test("a gap under a minute is said in seconds, and past it as a clock")
    func gapWording() {
        #expect(SudokuComparison.gapText(1) == "1s")
        #expect(SudokuComparison.gapText(48) == "48s")
        #expect(SudokuComparison.gapText(59) == "59s")
        #expect(SudokuComparison.gapText(60) == "1:00")
        #expect(SudokuComparison.gapText(187) == "3:07")
    }

    @Test("the verdict names whoever actually won")
    func verdictNames() {
        #expect(comparison(mine: 134, theirs: 182).verdict == "You finished 48s ahead.")
        #expect(comparison(mine: 604, theirs: 417).verdict == "Erin finished 3:07 ahead.")
    }

    @Test("a dead heat states the shared time instead of a margin")
    func tieVerdict() {
        #expect(comparison(mine: 240, theirs: 240).verdict == "A dead heat — you both took 4:00.")
    }

    /// The partner's name is whatever they typed, and it lands mid-sentence.
    @Test("an awkward partner name still produces a sentence")
    func unusualNames() {
        let odd = SudokuComparison(myElapsed: 300, partnerElapsed: 100, partnerName: "Zoë-Mae")
        #expect(odd.verdict == "Zoë-Mae finished 3:20 ahead.")
    }
}
