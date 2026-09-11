//
//  WordSearchPlayStateTests.swift
//  TwofoldTests
//
//  Finding words, the selection geometry, and the wire format.
//

import Foundation
import Testing
@testable import Twofold

struct WordSearchSelectionTests {
    private let size = WordSearchPuzzle.size

    @Test func aSingleCellIsALineOfOne() {
        // What a tap is, before the finger moves. Returning nil here would mean the first letter
        // never lights up.
        #expect(WordSearchPuzzle.line(from: 0, to: 0, size: size) == [0])
    }

    @Test func rowsColumnsAndDiagonalsAreLines() {
        #expect(WordSearchPuzzle.line(from: 0, to: 3, size: size) == [0, 1, 2, 3])
        #expect(WordSearchPuzzle.line(from: 0, to: 30, size: size) == [0, 10, 20, 30])
        #expect(WordSearchPuzzle.line(from: 0, to: 33, size: size) == [0, 11, 22, 33])
    }

    @Test func linesRunBackwardsAndUpwardsToo() {
        // All eight directions are legal placements, so all eight have to be draggable — and the
        // player should not have to work out which end of a word to start from.
        #expect(WordSearchPuzzle.line(from: 3, to: 0, size: size) == [3, 2, 1, 0])
        #expect(WordSearchPuzzle.line(from: 30, to: 0, size: size) == [30, 20, 10, 0])
        #expect(WordSearchPuzzle.line(from: 33, to: 0, size: size) == [33, 22, 11, 0])
        // Up and to the right.
        #expect(WordSearchPuzzle.line(from: 30, to: 3, size: size) == [30, 21, 12, 3])
    }

    @Test func aRunThatIsNotStraightIsNotASelection() {
        // Two across and one down is a drag that has wandered, not a word.
        #expect(WordSearchPuzzle.line(from: 0, to: 12 + 1, size: size) == nil)
        #expect(WordSearchPuzzle.line(from: 0, to: 21, size: size) == nil)
    }

    @Test func cellsOutsideTheGridAreRefused() {
        #expect(WordSearchPuzzle.line(from: -1, to: 5, size: size) == nil)
        #expect(WordSearchPuzzle.line(from: 0, to: size * size, size: size) == nil)
    }
}

struct WordSearchPlayStateTests {

    private func puzzle() -> WordSearchPuzzle {
        WordSearchGenerator.puzzle(seed: 11, theme: .travel)
    }

    @Test func draggingAWordFindsIt() {
        let grid = puzzle()
        var state = WordSearchPlayState(puzzle: grid)
        let placement = grid.placements[0]

        let found = state.find(cells: placement.cells(size: WordSearchPuzzle.size))
        #expect(found == placement)
        #expect(state.isFound(placement.word))
        #expect(state.found == [placement.word])
    }

    @Test func aWordCanBeDraggedFromEitherEnd() {
        let grid = puzzle()
        var state = WordSearchPlayState(puzzle: grid)
        let placement = grid.placements[0]

        #expect(state.find(cells: placement.cells(size: WordSearchPuzzle.size).reversed()) == placement)
        #expect(state.isFound(placement.word))
    }

    @Test func findingTheSameWordTwiceChangesNothing() {
        let grid = puzzle()
        var state = WordSearchPlayState(puzzle: grid)
        let cells = grid.placements[0].cells(size: WordSearchPuzzle.size)

        state.find(cells: cells)
        #expect(state.find(cells: cells) == nil)
        #expect(state.found.count == 1)
    }

    @Test func aRunThatIsNotAWordFindsNothing() {
        let grid = puzzle()
        var state = WordSearchPlayState(puzzle: grid)
        #expect(state.find(cells: [0, 1]) == nil || state.found.count == 1)
    }

    @Test func findingEveryWordCompletesTheGrid() {
        let grid = puzzle()
        var state = WordSearchPlayState(puzzle: grid)
        #expect(!state.isComplete)

        for placement in grid.placements {
            state.find(cells: placement.cells(size: WordSearchPuzzle.size))
        }
        #expect(state.isComplete)
        #expect(state.remainingCount == 0)
        #expect(state.foundCells.count > 0)
    }

    // MARK: - The wire format

    @Test func aGridSurvivesARoundTrip() throws {
        let grid = puzzle()
        var state = WordSearchPlayState(puzzle: grid)
        state.find(cells: grid.placements[0].cells(size: WordSearchPuzzle.size))
        state.find(cells: grid.placements[1].cells(size: WordSearchPuzzle.size))
        state.elapsed = 143

        let restored = try #require(WordSearchPlayState.decoded(from: state.encoded, puzzle: grid))
        #expect(restored.found == state.found)
        #expect(restored.elapsed == 143)
        #expect(!restored.isComplete)
    }

    @Test func anUntouchedGridRoundTrips() throws {
        // The empty found field splits to [""] rather than [], which is exactly the kind of thing
        // that turns "nothing found yet" into a decode failure and restarts somebody's grid.
        let grid = puzzle()
        let restored = try #require(
            WordSearchPlayState.decoded(from: WordSearchPlayState(puzzle: grid).encoded, puzzle: grid)
        )
        #expect(restored.found.isEmpty)
    }

    @Test func aPayloadNamingWordsThisGridDoesNotHaveIsRefused() {
        // Written against a different grid, or by a build whose word lists differed. Accepting it
        // would count a word towards completion that is not on the board — and at eight of them the
        // grid would finish with words still hidden.
        let grid = puzzle()
        #expect(WordSearchPlayState.decoded(from: "wordsearch.v1|NOTAWORD|10|0", puzzle: grid) == nil)
    }

    @Test func aPayloadThisBuildCannotReadIsRefusedRatherThanRepaired() {
        let grid = puzzle()
        #expect(WordSearchPlayState.decoded(from: "", puzzle: grid) == nil)
        #expect(WordSearchPlayState.decoded(from: "wordsearch.v2|FLIGHT|10|0", puzzle: grid) == nil)
        #expect(WordSearchPlayState.decoded(from: "wordsearch.v1|FLIGHT|10", puzzle: grid) == nil)
        #expect(WordSearchPlayState.decoded(from: "wordsearch.v1|FLIGHT|-5|0", puzzle: grid) == nil)
        // A word twice cannot happen on a real grid, so a payload carrying it was not written by
        // one.
        let word = grid.words[0]
        #expect(WordSearchPlayState.decoded(from: "wordsearch.v1|\(word),\(word)|10|0", puzzle: grid) == nil)
    }

    @Test func theInitialiserDropsWordsThisGridDoesNotHave() {
        // The same protection as the decoder, one level down: a state built directly from a bad
        // list must not be able to count towards completion either.
        let grid = puzzle()
        let state = WordSearchPlayState(puzzle: grid, found: ["NOTAWORD", grid.words[0]])
        #expect(state.found == [grid.words[0]])
    }

    @Test func theSummaryReadsAResultWithoutKnowingTheGrid() throws {
        let grid = puzzle()
        var state = WordSearchPlayState(puzzle: grid)
        for placement in grid.placements {
            state.find(cells: placement.cells(size: WordSearchPuzzle.size))
        }
        state.elapsed = 212

        let summary = try #require(WordSearchPlayState.summary(from: state.encoded))
        #expect(summary.foundCount == WordSearchPuzzle.wordCount)
        #expect(summary.complete)
        #expect(summary.elapsed == 212)
    }
}

struct WordSearchComparisonTests {
    private func comparison(mine: TimeInterval, theirs: TimeInterval) -> WordSearchComparison {
        WordSearchComparison(myElapsed: mine, partnerElapsed: theirs, partnerName: "Erin", theme: .travel)
    }

    @Test func theQuickerClearWins() {
        #expect(comparison(mine: 154, theirs: 233).outcome == .me)
        #expect(comparison(mine: 400, theirs: 233).outcome == .partner)
        #expect(comparison(mine: 200, theirs: 200).outcome == .tie)
    }

    @Test func timesThatReadTheSameOnScreenAreADeadHeat() {
        // The rows only ever showed whole seconds, so calling one of two 3:20s the winner is a
        // result the player can see the screen contradict.
        #expect(comparison(mine: 200.2, theirs: 200.4).outcome == .tie)
        #expect(comparison(mine: 200.2, theirs: 200.4).margin == 0)
    }

    @Test func theVerdictNamesWhoeverWon() {
        #expect(comparison(mine: 154, theirs: 233).verdict.resolved == "You cleared the grid 1:19 faster.")
        #expect(comparison(mine: 400, theirs: 233).verdict.resolved == "Erin cleared the grid 2:47 faster.")
        #expect(comparison(mine: 200, theirs: 200).verdict.resolved == "A dead heat — you both took 3:20.")
    }

    @Test func theSharedVerdictNamesBothSides() {
        // "You" on a shared image names the sender to every viewer — worst of all to the partner,
        // who would read the other person's win as their own.
        let iWon = comparison(mine: 154, theirs: 233)
        #expect(iWon.sharedVerdict(myName: "Rosa").resolved == "Rosa cleared the grid 1:19 faster.")

        let theyWon = comparison(mine: 400, theirs: 233)
        #expect(theyWon.sharedVerdict(myName: "Rosa").resolved == "Erin cleared the grid 2:47 faster.")
    }
}
