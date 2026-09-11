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
        #expect(comparison(mine: 134.0, theirs: 134.49).verdict.resolved.contains("dead heat"))
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
        #expect(close.verdict.resolved == "You finished 6s ahead.")
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
        #expect(comparison(mine: 134, theirs: 182).verdict.resolved == "You finished 48s ahead.")
        #expect(comparison(mine: 604, theirs: 417).verdict.resolved == "Erin finished 3:07 ahead.")
    }

    @Test("a dead heat states the shared time instead of a margin")
    func tieVerdict() {
        #expect(comparison(mine: 240, theirs: 240).verdict.resolved == "A dead heat — you both took 4:00.")
    }

    // MARK: - How it reads on a card that leaves the device

    /// "You" on a shared image names the sender to every viewer — worst of all to the partner it
    /// gets sent to, who would read the other person's win as their own.
    @Test("the shared verdict names the winner instead of saying 'you'")
    func sharedVerdictNamesBothSides() {
        let iWon = comparison(mine: 134, theirs: 182)
        #expect(iWon.verdict.resolved == "You finished 48s ahead.")
        #expect(iWon.sharedVerdict(myName: "Rosa").resolved == "Rosa finished 48s ahead.")

        let theyWon = comparison(mine: 604, theirs: 417)
        #expect(theyWon.sharedVerdict(myName: "Rosa").resolved == "Erin finished 3:07 ahead.")
    }

    @Test("a shared dead heat drops 'you both' too")
    func sharedTieVerdict() {
        let tie = comparison(mine: 240, theirs: 240)
        #expect(tie.verdict.resolved == "A dead heat — you both took 4:00.")
        #expect(tie.sharedVerdict(myName: "Rosa").resolved == "A dead heat — 4:00 each.")
    }

    /// The partner's name is whatever they typed, and it lands mid-sentence.
    @Test("an awkward partner name still produces a sentence")
    func unusualNames() {
        let odd = SudokuComparison(myElapsed: 300, partnerElapsed: 100, partnerName: "Zoë-Mae")
        #expect(odd.verdict.resolved == "Zoë-Mae finished 3:20 ahead.")
    }
}

//
//  What help was used, and saying so.
//
//  The competitive framing is the whole point of sudoku here, and it only survives if the times are
//  comparable. A hint button that leaves no trace doesn't make the race easier — it ends it, by
//  rewarding whoever was most willing to ask. So the counts ride alongside the times, and the one
//  case that needs saying outright is one player solving cold while the other didn't.
//
struct SudokuAidsTests {

    private func summary(hints: Int, checks: Int, elapsed: TimeInterval = 300) -> SudokuSolveSummary {
        SudokuSolveSummary(elapsed: elapsed, hintsUsed: hints, checksUsed: checks)
    }

    @Test("an unaided solve says nothing rather than 'no help'")
    func unaidedIsSilent() {
        let clean = summary(hints: 0, checks: 0)
        #expect(clean.isUnaided)
        // nil, not "no help" — printed under both times on the ordinary solve it reads as an
        // accusation rather than a footnote.
        #expect(clean.aidsDescription == nil)
    }

    /// Two of these come from the String Catalog's plural rules rather than from Swift, so this is
    /// also the test that the catalog's plural entries are wired up and resolving — a broken
    /// variation would show as "1 hints" here rather than as a build failure.
    ///
    /// Two was "checked twice" until the plural keys landed. English has a word for exactly two and
    /// most languages do not; it is not a plural category, so it cannot be expressed as one, and
    /// keeping it would have meant a Swift branch no translator could reproduce. Losing it is a
    /// small cost in English for a rule that works everywhere else.
    @Test("hints and checks are counted in words", arguments: [
        (1, 0, "1 hint"),
        (3, 0, "3 hints"),
        (0, 1, "checked once"),
        (0, 2, "checked 2 times"),
        (0, 5, "checked 5 times"),
        (2, 1, "2 hints, checked once"),
    ])
    func aidsRead(hints: Int, checks: Int, expected: String) {
        #expect(summary(hints: hints, checks: checks).aidsDescription == expected)
    }

    @Test("one solving cold and the other not is flagged, in either direction")
    func lopsidedBothWays() {
        let clean = summary(hints: 0, checks: 0)
        let helped = summary(hints: 2, checks: 0)

        var mineClean = SudokuComparison(myElapsed: 300, partnerElapsed: 400, partnerName: "Erin")
        mineClean.myAids = clean
        mineClean.partnerAids = helped
        #expect(mineClean.isLopsided)

        var theirsClean = SudokuComparison(myElapsed: 300, partnerElapsed: 400, partnerName: "Erin")
        theirsClean.myAids = helped
        theirsClean.partnerAids = clean
        #expect(theirsClean.isLopsided)
    }

    @Test("two clean solves, or two helped ones, are a fair race")
    func evenlyMatchedIsNotFlagged() {
        var bothClean = SudokuComparison(myElapsed: 300, partnerElapsed: 400, partnerName: "Erin")
        bothClean.myAids = summary(hints: 0, checks: 0)
        bothClean.partnerAids = summary(hints: 0, checks: 0)
        #expect(!bothClean.isLopsided)

        // Different amounts of help, but both asked — a matter of degree, not of kind, and not
        // something to caption a couple's game with.
        var bothHelped = SudokuComparison(myElapsed: 300, partnerElapsed: 400, partnerName: "Erin")
        bothHelped.myAids = summary(hints: 1, checks: 0)
        bothHelped.partnerAids = summary(hints: 4, checks: 3)
        #expect(!bothHelped.isLopsided)
    }

    /// A v1 solve has no counts at all, so nothing can be claimed about fairness either way.
    @Test("with either side's help unknown, nothing is claimed")
    func unknownAidsAreNotLopsided() {
        var partial = SudokuComparison(myElapsed: 300, partnerElapsed: 400, partnerName: "Erin")
        partial.myAids = summary(hints: 0, checks: 0)
        partial.partnerAids = nil
        #expect(!partial.isLopsided)
    }
}
