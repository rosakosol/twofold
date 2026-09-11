//
//  ConnectFourBoardTests.swift
//  TwofoldTests
//
//  The same cases `connect_four_test.sql` checks the server's copy against.
//
//  There are two implementations of these rules — this one draws the board, the SQL one ends the
//  game — and the thing that makes that survivable is that they agree. So the cases are deliberately
//  the same ones, in the same four directions, including the wrap-around that in a flat array looks
//  exactly like a win nobody made.
//

import Testing
@testable import Twofold

struct ConnectFourBoardTests {

    /// Builds a board from a picture, bottom row last. `.` empty, `x` first player, `o` second.
    private func board(_ rows: [String]) -> ConnectFourBoard {
        var board = ConnectFourBoard()
        var cells = [ConnectFourBoard.Disc?](repeating: nil, count: 42)
        for (row, line) in rows.enumerated() {
            for (column, character) in Array(line).enumerated() {
                cells[row * 7 + column] = character == "x" ? .first : character == "o" ? .second : nil
            }
        }
        // Replayed through `drop` rather than assigned, so the fixture cannot describe a board
        // gravity would never produce.
        for column in 0..<7 {
            for row in stride(from: 5, through: 0, by: -1) {
                if let disc = cells[row * 7 + column] { board.drop(in: column, as: disc) }
            }
        }
        return board
    }

    // MARK: - Gravity

    @Test func aDiscFallsToTheBottom() {
        var board = ConnectFourBoard()
        #expect(board.drop(in: 3, as: .first) == 5)
        #expect(board[5, 3] == .first)
        #expect(board[0, 3] == nil)
    }

    @Test func discsStack() {
        var board = ConnectFourBoard()
        #expect(board.drop(in: 3, as: .first) == 5)
        #expect(board.drop(in: 3, as: .second) == 4)
        #expect(board.drop(in: 3, as: .first) == 3)
    }

    @Test func aFullColumnTakesNoMore() {
        var board = ConnectFourBoard()
        for index in 0..<6 { board.drop(in: 0, as: index % 2 == 0 ? .first : .second) }
        #expect(board.landingRow(in: 0) == nil)
        #expect(board.drop(in: 0, as: .first) == nil)
        #expect(!board.playableColumns.contains(0))
        #expect(board.playableColumns.count == 6)
    }

    @Test func columnsOutsideTheBoardAreRefused() {
        var board = ConnectFourBoard()
        #expect(board.landingRow(in: -1) == nil)
        #expect(board.landingRow(in: 7) == nil)
        #expect(board.drop(in: 7, as: .first) == nil)
    }

    @Test func replayingColumnsAlternatesPlayers() {
        // The order *is* the record of who played what — turns strictly alternate, so a second copy
        // of that fact is one that can disagree.
        let board = ConnectFourBoard(droppedColumns: [3, 3, 4])
        #expect(board[5, 3] == .first)
        #expect(board[4, 3] == .second)
        #expect(board[5, 4] == .first)
    }

    // MARK: - Winning, in every direction

    @Test func anEmptyBoardHasNoWinner() {
        #expect(ConnectFourBoard().winner == nil)
        #expect(!ConnectFourBoard().isFinished)
    }

    @Test func fourAcrossWins() {
        let b = board([
            ".......",
            ".......",
            ".......",
            ".......",
            ".......",
            ".xxxx..",
        ])
        #expect(b.winner == .first)
        #expect(b.winningLine()?.cells.count == 4)
    }

    @Test func fourDownWins() {
        let b = board([
            ".......",
            ".......",
            "..o....",
            "..o....",
            "..o....",
            "..o....",
        ])
        #expect(b.winner == .second)
    }

    @Test func fourOnADownRightDiagonalWins() {
        let b = board([
            ".......",
            ".......",
            ".x.....",
            "oox....",
            "oxox...",
            "xooox..",
        ])
        #expect(b.winner == .first)
    }

    @Test func fourOnADownLeftDiagonalWins() {
        let b = board([
            ".......",
            ".......",
            ".....o.",
            "....ox.",
            "...oxx.",
            "..oxxx.",
        ])
        #expect(b.winner == .second)
    }

    // MARK: - What is not a win

    @Test func threeInARowIsNotAWin() {
        let b = board([
            ".......",
            ".......",
            ".......",
            ".......",
            ".......",
            ".xxx...",
        ])
        #expect(b.winner == nil)
    }

    @Test func aRunSplitByTheOtherPlayerIsNotAWin() {
        let b = board([
            ".......",
            ".......",
            ".......",
            ".......",
            ".......",
            ".xxoxx.",
        ])
        #expect(b.winner == nil)
    }

    @Test func aRunThatWrapsTheEdgeOfTheBoardIsNotAWin() {
        // The classic flat-array bug. Row 4's last two columns and row 5's first two are indices
        // 33, 34, 35 and 36 — four consecutive entries holding the same player, with nothing on
        // screen connecting them. A scan that walks the array instead of the grid calls this a win.
        let b = board([
            ".......",
            ".......",
            ".......",
            ".......",
            ".....xx",
            "xx...oo",
        ])
        #expect(b[4, 5] == .first)
        #expect(b[4, 6] == .first)
        #expect(b[5, 0] == .first)
        #expect(b[5, 1] == .first)
        #expect(b.winner == nil)
    }

    // MARK: - Draws

    @Test func aFullBoardWithNoLineIsADraw() {
        // Columns filled in an order that leaves no four anywhere: each column alternates, and
        // adjacent columns start with different players.
        var board = ConnectFourBoard()
        let pattern: [[ConnectFourBoard.Disc]] = (0..<7).map { column in
            (0..<6).map { row in
                // Two rows of one player, then two of the other, offset per column — the standard
                // way to fill a 7x6 with no line.
                ((row / 2) + column) % 2 == 0 ? .first : .second
            }
        }
        for column in 0..<7 {
            for row in 0..<6 { board.drop(in: column, as: pattern[column][row]) }
        }
        #expect(board.isFull)
        // Asserted outright rather than guarded by `if winner == nil`. A guard would make this test
        // pass whether or not the fill happens to contain a line, which is the opposite of what it
        // is for.
        #expect(board.winner == nil)
        #expect(board.isDraw)
        #expect(board.isFinished)
    }

    @Test func aBoardWithAWinIsNotADraw() {
        let b = board([
            ".......",
            ".......",
            ".......",
            ".......",
            ".......",
            ".xxxx..",
        ])
        #expect(!b.isDraw)
        #expect(b.isFinished)
    }
}
