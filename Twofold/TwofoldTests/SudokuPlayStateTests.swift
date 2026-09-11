//
//  SudokuPlayStateTests.swift
//  TwofoldTests
//
//  Two things here are worth more than the rest.
//
//  The decoder is a parser for a string that arrives from the network, and its failure mode is
//  silent: a grid rebuilt out of a half-understood payload looks exactly like a grid. So it is
//  tested by what it REFUSES, one malformation at a time, and by the rule that the puzzle's own
//  numbers are re-imposed on whatever came back — no stored string can make a given disappear.
//
//  And the conflict highlight returns both offenders rather than the later one, because a board
//  that lights up one of a duplicated pair is telling the player the other is fine.
//

import Testing
import Foundation
@testable import Twofold

struct SudokuPlayStateTests {

    private static let generated = SudokuGenerator.puzzle(seed: 4_242, difficulty: .medium)
    private var puzzle: SudokuGrid { Self.generated.puzzle }
    private var solution: SudokuGrid { Self.generated.solution }

    /// The first empty cell, so tests write where writing is allowed.
    private var firstEmpty: Int { (0..<81).first { puzzle[$0] == 0 }! }
    private var firstGiven: Int { (0..<81).first { puzzle[$0] != 0 }! }

    // MARK: - Round trip

    @Test("a played state survives encoding and decoding")
    func roundTrips() {
        var state = SudokuPlayState(puzzle: puzzle)
        state.place(5, at: firstEmpty, puzzle: puzzle)
        state.toggleNote(3, at: (0..<81).filter { puzzle[$0] == 0 }[1], puzzle: puzzle)
        state.toggleNote(7, at: (0..<81).filter { puzzle[$0] == 0 }[1], puzzle: puzzle)
        state.elapsed = 137

        let restored = SudokuPlayState.decoded(from: state.encoded, puzzle: puzzle)
        #expect(restored == state)
    }

    @Test("a fresh state round trips too")
    func freshRoundTrips() {
        let state = SudokuPlayState(puzzle: puzzle)
        #expect(SudokuPlayState.decoded(from: state.encoded, puzzle: puzzle) == state)
    }

    @Test("completion survives the round trip")
    func completionRoundTrips() {
        var state = SudokuPlayState(puzzle: puzzle)
        state.markComplete()
        #expect(SudokuPlayState.decoded(from: state.encoded, puzzle: puzzle)?.isComplete == true)
    }

    // MARK: - What the decoder refuses

    /// Each of these is a real way a payload goes wrong: an old version still on another device, a
    /// truncated write, a value that never came from `toggleNote`.
    @Test("malformed payloads are refused rather than half-read", arguments: [
        "",
        "sudoku.v1",
        "sudoku.v2|" + String(repeating: "0", count: 81) + "|" + String(repeating: "000", count: 81) + "|0|0",
        // 80 cells, not 81.
        "sudoku.v1|" + String(repeating: "0", count: 80) + "|" + String(repeating: "000", count: 81) + "|0|0",
        // A digit outside 0...9.
        "sudoku.v1|x" + String(repeating: "0", count: 80) + "|" + String(repeating: "000", count: 81) + "|0|0",
        // Notes field one group short.
        "sudoku.v1|" + String(repeating: "0", count: 81) + "|" + String(repeating: "000", count: 80) + "|0|0",
        // Not hex.
        "sudoku.v1|" + String(repeating: "0", count: 81) + "|zzz" + String(repeating: "000", count: 80) + "|0|0",
        // Bit 0 set — no note can produce it.
        "sudoku.v1|" + String(repeating: "0", count: 81) + "|001" + String(repeating: "000", count: 80) + "|0|0",
        // Bit 10 set — likewise.
        "sudoku.v1|" + String(repeating: "0", count: 81) + "|400" + String(repeating: "000", count: 80) + "|0|0",
        // Negative time.
        "sudoku.v1|" + String(repeating: "0", count: 81) + "|" + String(repeating: "000", count: 81) + "|-1|0",
        // A completion flag that is neither.
        "sudoku.v1|" + String(repeating: "0", count: 81) + "|" + String(repeating: "000", count: 81) + "|0|maybe",
    ])
    func refusesMalformed(payload: String) {
        #expect(SudokuPlayState.decoded(from: payload, puzzle: puzzle) == nil)
    }

    /// The negative control for the list above: a payload of exactly that shape, correct, is
    /// accepted. Without it every refusal could be a decoder that refuses everything.
    @Test("a well-formed payload of the same shape is accepted")
    func acceptsWellFormed() {
        let payload = "sudoku.v1|" + String(repeating: "0", count: 81)
            + "|" + String(repeating: "000", count: 81) + "|0|0"
        #expect(SudokuPlayState.decoded(from: payload, puzzle: puzzle) != nil)
    }

    /// The givens are the puzzle. A payload claiming otherwise — stale, truncated mid-write, or
    /// simply from a different puzzle — must not be able to blank one out.
    @Test("no stored payload can erase a given")
    func givensAreReimposed() {
        let empty = "sudoku.v1|" + String(repeating: "0", count: 81)
            + "|" + String(repeating: "000", count: 81) + "|0|0"
        let restored = SudokuPlayState.decoded(from: empty, puzzle: puzzle)
        #expect(restored != nil)
        for index in 0..<81 where puzzle[index] != 0 {
            #expect(restored?[index] == puzzle[index], "cell \(index) lost its given")
        }
    }

    // MARK: - Playing

    @Test("a given cannot be written over")
    func givensAreReadOnly() {
        var state = SudokuPlayState(puzzle: puzzle)
        let original = state[firstGiven]
        state.place(original == 1 ? 2 : 1, at: firstGiven, puzzle: puzzle)
        #expect(state[firstGiven] == original)

        state.erase(at: firstGiven, puzzle: puzzle)
        #expect(state[firstGiven] == original, "erase must not empty a given either")

        state.toggleNote(4, at: firstGiven, puzzle: puzzle)
        #expect(state.note(4, at: firstGiven) == false, "nor can a given carry pencil marks")
    }

    /// The tedious bit of playing on paper, and the reason a stale note is worse than no note: it
    /// says a cell can take a digit the board has already ruled out.
    @Test("placing a digit rubs it out of the notes of every cell that can no longer hold it")
    func placingClearsPeerNotes() {
        var state = SudokuPlayState(puzzle: puzzle)
        let target = firstEmpty
        let peers = SudokuPlayState.peers(of: target).filter { puzzle[$0] == 0 }
        #expect(!peers.isEmpty)

        for peer in peers {
            state.toggleNote(6, at: peer, puzzle: puzzle)
            state.toggleNote(2, at: peer, puzzle: puzzle)
        }
        state.place(6, at: target, puzzle: puzzle)

        for peer in peers {
            #expect(state.note(6, at: peer) == false, "cell \(peer) kept a note the placement ruled out")
            #expect(state.note(2, at: peer) == true, "and must keep the notes it did not rule out")
        }
    }

    @Test("a note and a digit cannot occupy the same cell")
    func notesAndDigitsAreExclusive() {
        var state = SudokuPlayState(puzzle: puzzle)
        let target = firstEmpty

        state.place(8, at: target, puzzle: puzzle)
        state.toggleNote(1, at: target, puzzle: puzzle)
        #expect(state[target] == 0, "writing a note clears the digit")
        #expect(state.note(1, at: target))

        state.place(8, at: target, puzzle: puzzle)
        #expect(state.note(1, at: target) == false, "and writing a digit clears the notes")
    }

    @Test("a note toggles off")
    func notesToggle() {
        var state = SudokuPlayState(puzzle: puzzle)
        state.toggleNote(9, at: firstEmpty, puzzle: puzzle)
        state.toggleNote(9, at: firstEmpty, puzzle: puzzle)
        #expect(state.note(9, at: firstEmpty) == false)
    }

    // MARK: - Conflicts

    @Test("an untouched puzzle has no conflicts")
    func freshPuzzleIsClean() {
        #expect(SudokuPlayState(puzzle: puzzle).conflicts().isEmpty)
    }

    /// Both cells, not one. A board that highlights only the second of a duplicated pair is saying
    /// the first is correct.
    @Test("a duplicate lights up both cells")
    func conflictsIncludeBothOffenders() {
        var state = SudokuPlayState(puzzle: puzzle)
        // Two empty cells sharing a row.
        let row = (0..<9).first { r in (0..<9).filter { puzzle[r * 9 + $0] == 0 }.count >= 2 }!
        let cells = (0..<9).filter { puzzle[row * 9 + $0] == 0 }.prefix(2).map { row * 9 + $0 }

        state.place(4, at: cells[0], puzzle: puzzle)
        state.place(4, at: cells[1], puzzle: puzzle)

        let conflicts = state.conflicts()
        #expect(conflicts.contains(cells[0]))
        #expect(conflicts.contains(cells[1]))
    }

    @Test("clearing one of the pair clears the highlight")
    func conflictsClear() {
        var state = SudokuPlayState(puzzle: puzzle)
        let row = (0..<9).first { r in (0..<9).filter { puzzle[r * 9 + $0] == 0 }.count >= 2 }!
        let cells = (0..<9).filter { puzzle[row * 9 + $0] == 0 }.prefix(2).map { row * 9 + $0 }
        state.place(4, at: cells[0], puzzle: puzzle)
        state.place(4, at: cells[1], puzzle: puzzle)
        state.erase(at: cells[1], puzzle: puzzle)
        #expect(state.conflicts().isEmpty)
    }

    // MARK: - Finishing

    @Test("the solution is recognised as solved")
    func solvedGridIsSolved() {
        var state = SudokuPlayState(puzzle: puzzle)
        for index in 0..<81 where puzzle[index] == 0 {
            state.place(solution[index], at: index, puzzle: puzzle)
        }
        #expect(state.isSolved(solution: solution))
        #expect(state.conflicts().isEmpty)
    }

    @Test("one wrong cell is not solved")
    func nearlySolvedIsNotSolved() {
        var state = SudokuPlayState(puzzle: puzzle)
        let empties = (0..<81).filter { puzzle[$0] == 0 }
        for index in empties { state.place(solution[index], at: index, puzzle: puzzle) }
        let last = empties.last!
        state.place(solution[last] == 9 ? 1 : 9, at: last, puzzle: puzzle)
        #expect(state.isSolved(solution: solution) == false)
    }

    // MARK: - Peers

    /// 20, every time: 8 along the row, 8 down the column, and 4 more from the box.
    @Test("every cell has exactly twenty peers, and is not one of them")
    func peersAreWellFormed() {
        for index in 0..<81 {
            let peers = SudokuPlayState.peers(of: index)
            #expect(peers.count == 20, "cell \(index) has \(peers.count) peers")
            #expect(!peers.contains(index))
            #expect(Set(peers).count == 20, "cell \(index) lists a peer twice")
        }
    }

    @Test("peers are exactly the shared row, column and box")
    func peersAreTheRightCells() {
        let index = 40 // centre of the grid, centre of its box
        let peers = Set(SudokuPlayState.peers(of: index))
        #expect(peers.contains(36))  // same row
        #expect(peers.contains(4))   // same column
        #expect(peers.contains(30))  // same box
        #expect(!peers.contains(0))  // shares nothing with the centre
    }

    // MARK: - The stats-side reader

    /// `summary` exists so stats can read a time without regenerating the puzzle `decoded` needs.
    /// Two readers of one format is exactly how a format drifts, so this pins them together: every
    /// payload they both accept has to yield the same two fields.
    @Test("summary agrees with decoded about the time and whether it was finished")
    func summaryMatchesDecoded() throws {
        var play = SudokuPlayState(puzzle: puzzle)
        play.elapsed = 754
        let midway = play.encoded
        let decodedMidway = try #require(SudokuPlayState.decoded(from: midway, puzzle: puzzle))
        let summaryMidway = try #require(SudokuPlayState.summary(from: midway))
        #expect(summaryMidway.elapsed == decodedMidway.elapsed)
        #expect(summaryMidway.isComplete == decodedMidway.isComplete)
        #expect(summaryMidway.isComplete == false)

        play.markComplete()
        let finished = play.encoded
        let decodedFinished = try #require(SudokuPlayState.decoded(from: finished, puzzle: puzzle))
        let summaryFinished = try #require(SudokuPlayState.summary(from: finished))
        #expect(summaryFinished.elapsed == decodedFinished.elapsed)
        #expect(summaryFinished.isComplete == decodedFinished.isComplete)
        #expect(summaryFinished.isComplete)
    }

    /// Both readers have to refuse the same rubbish. A `summary` that were laxer would let a
    /// payload `decoded` rejects still reach the stats table — as a best time, where a wrong small
    /// number is unbeatable and permanent.
    @Test("summary refuses everything decoded refuses", arguments: [
        "",
        "sudoku.v2|0|0|10|1",
        "sudoku.v1|0|0|10",
        "sudoku.v1|0|0|-5|1",
        "sudoku.v1|0|0|10|2",
        "not a payload at all",
    ])
    func summaryIsAsStrictAsDecoded(payload: String) {
        #expect(SudokuPlayState.summary(from: payload) == nil)
        #expect(SudokuPlayState.decoded(from: payload, puzzle: puzzle) == nil)
    }
}

//
//  Reading v1 after v2 exists.
//
//  Hints and checks added two fields, so the payload became `sudoku.v2`. Every puzzle solved before
//  that is a v1 row already sitting in `game_responses`, and those rows are what the stats table,
//  the head-to-head record and the resume path all read. A decoder that only understood v2 would
//  not crash — it would return nil, and every one of those would quietly become "no history".
//
//  The other direction matters too: a v2 payload reaching a build that predates it must be refused
//  outright rather than read as a v1 with extra junk on the end, which would restore a grid and a
//  time while silently dropping the hint count that made them mean something.
//
struct SudokuPayloadVersionTests {

    private static let generated = SudokuGenerator.puzzle(seed: 99, difficulty: .easy)
    private var puzzle: SudokuGrid { Self.generated.puzzle }

    private func v1(elapsed: Int, complete: Bool) -> String {
        "sudoku.v1|" + String(repeating: "0", count: 81)
            + "|" + String(repeating: "000", count: 81)
            + "|\(elapsed)|\(complete ? 1 : 0)"
    }

    @Test("a v1 payload still decodes, as a solve with no help used")
    func v1DecodesAsUnaided() throws {
        let restored = try #require(SudokuPlayState.decoded(from: v1(elapsed: 754, complete: true), puzzle: puzzle))
        #expect(restored.elapsed == 754)
        #expect(restored.isComplete)
        // True of it, rather than a default standing in for missing data: there was no way to use
        // either when that row was written.
        #expect(restored.hintsUsed == 0)
        #expect(restored.checksUsed == 0)
        #expect(restored.isUnaided)
    }

    @Test("summary reads v1 too — it is what the stats table runs on")
    func v1Summarises() throws {
        let summary = try #require(SudokuPlayState.summary(from: v1(elapsed: 312, complete: true)))
        #expect(summary.elapsed == 312)
        #expect(summary.isComplete)
        #expect(summary.hintsUsed == 0)
        #expect(summary.checksUsed == 0)
    }

    @Test("what gets written is v2, carrying the counts")
    func writesV2() {
        var play = SudokuPlayState(puzzle: puzzle)
        play.revealCell(at: (0..<81).first { puzzle[$0] == 0 }!, solution: Self.generated.solution, puzzle: puzzle)
        play.recordCheck()
        play.recordCheck()

        #expect(play.encoded.hasPrefix("sudoku.v2|"))
        let restored = SudokuPlayState.decoded(from: play.encoded, puzzle: puzzle)
        #expect(restored?.hintsUsed == 1)
        #expect(restored?.checksUsed == 2)
        #expect(restored?.isUnaided == false)
    }

    /// A v1 string with two fields bolted on is not a v2 — the version is what says how to read it,
    /// and guessing from the field count is how a format starts being read wrong.
    @Test("the version and the field count have to agree", arguments: [
        // v1 claimed, v2 shape.
        "sudoku.v1|" + String(repeating: "0", count: 81) + "|" + String(repeating: "000", count: 81) + "|10|1|0|0",
        // v2 claimed, v1 shape.
        "sudoku.v2|" + String(repeating: "0", count: 81) + "|" + String(repeating: "000", count: 81) + "|10|1",
        // v2 with an unreadable count.
        "sudoku.v2|" + String(repeating: "0", count: 81) + "|" + String(repeating: "000", count: 81) + "|10|1|x|0",
        // v2 with a negative count.
        "sudoku.v2|" + String(repeating: "0", count: 81) + "|" + String(repeating: "000", count: 81) + "|10|1|0|-1",
    ])
    func mismatchedShapesAreRefused(payload: String) {
        #expect(SudokuPlayState.decoded(from: payload, puzzle: puzzle) == nil)
        // And both readers agree about it, which is the property that keeps them from drifting.
        #expect(SudokuPlayState.summary(from: payload) == nil)
    }
}
