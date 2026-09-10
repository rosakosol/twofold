//
//  SudokuProgressResumeTests.swift
//  TwofoldTests
//
//  Two copies of the same puzzle disagree more often than it sounds: a save that did not land, the
//  app killed mid-solve, the same puzzle opened on a second device. There is no sensible merge —
//  a cell holds one digit, and choosing per-cell would build a board neither person ever saw — so
//  the rule is to pick one whole, and these pin which.
//

import Testing
import Foundation
@testable import Twofold

struct SudokuProgressResumeTests {

    private static let generated = SudokuGenerator.puzzle(seed: 808, difficulty: .easy)
    private var puzzle: SudokuGrid { Self.generated.puzzle }

    private func state(elapsed: TimeInterval, complete: Bool = false) -> SudokuPlayState {
        var state = SudokuPlayState(puzzle: puzzle)
        state.elapsed = elapsed
        if complete { state.markComplete() }
        return state
    }

    @Test("with only one copy, that is the one")
    func singleCopyWins() {
        let only = state(elapsed: 30)
        #expect(SudokuPlayState.furtherAlong(only, nil) == only)
        #expect(SudokuPlayState.furtherAlong(nil, only) == only)
    }

    @Test("with no copy at all there is nothing to resume")
    func noCopy() {
        #expect(SudokuPlayState.furtherAlong(nil, nil) == nil)
    }

    /// Time at the board only ever climbs, and only while someone is looking at it, which makes it
    /// the closest available stand-in for "further on".
    @Test("the copy played longer wins")
    func longerPlayedWins() {
        let shorter = state(elapsed: 60)
        let longer = state(elapsed: 61)
        #expect(SudokuPlayState.furtherAlong(shorter, longer) == longer)
        #expect(SudokuPlayState.furtherAlong(longer, shorter) == longer)
    }

    /// The rule that overrides the clock. Having solved a puzzle is not something to be undone by
    /// a device that happened to sit open on the board for longer.
    @Test("a finished puzzle beats an unfinished one that took longer")
    func completionBeatsTime() {
        let solved = state(elapsed: 10, complete: true)
        let stillGoing = state(elapsed: 9_999)
        #expect(SudokuPlayState.furtherAlong(solved, stillGoing) == solved)
        #expect(SudokuPlayState.furtherAlong(stillGoing, solved) == solved)
    }

    @Test("two finished copies fall back to the clock")
    func twoCompleteFallBackToTime() {
        let quick = state(elapsed: 100, complete: true)
        let slow = state(elapsed: 200, complete: true)
        #expect(SudokuPlayState.furtherAlong(quick, slow) == slow)
    }

    // MARK: - The clock

    @Test("the clock reads as a time, not a number of seconds", arguments: [
        (TimeInterval(0), "0:00"),
        (TimeInterval(9), "0:09"),
        (TimeInterval(70), "1:10"),
        (TimeInterval(600), "10:00"),
        (TimeInterval(3_600), "1:00:00"),
        (TimeInterval(3_671), "1:01:11"),
    ])
    func clockFormatting(elapsed: TimeInterval, expected: String) {
        #expect(SudokuGameView.clockText(elapsed) == expected)
    }

    /// An hour is where a naive `%d:%02d` starts reading as "83:20" instead of "1:23:20", and Expert
    /// puzzles genuinely run that long.
    @Test("past an hour it grows a third field rather than counting to ninety minutes")
    func longSolves() {
        #expect(SudokuGameView.clockText(5_000) == "1:23:20")
    }
}
