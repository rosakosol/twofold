//
//  SudokuProgressCache.swift
//  Twofold
//
//  The half-finished grid, kept on the device.
//
//  The storage is `PuzzleProgressCache`, shared with every other generated game and documented
//  there. What lives here is the sudoku-shaped half: a state goes in, and comes back out decoded
//  against the grid it was played on.
//

import Foundation

/// Sudoku's own view of `PuzzleProgressCache` — the same store, with the decoding this game needs.
///
/// Kept as a type rather than folded into the call sites because decoding wants the puzzle, and a
/// cache that hands back a string every caller then has to remember to decode against the *right*
/// grid is a cache that will eventually be decoded against the wrong one.
enum SudokuProgressCache {
    private static let store = PuzzleProgressCache.sudoku

    static func save(_ state: SudokuPlayState, sessionID: UUID, responderID: UUID) {
        store.save(state.encoded, sessionID: sessionID, responderID: responderID)
    }

    static func load(sessionID: UUID, responderID: UUID, puzzle: SudokuGrid) -> SudokuPlayState? {
        guard let encoded = store.load(sessionID: sessionID, responderID: responderID) else { return nil }
        return SudokuPlayState.decoded(from: encoded, puzzle: puzzle)
    }

    static func remove(sessionID: UUID, responderID: UUID) {
        store.remove(sessionID: sessionID, responderID: responderID)
    }
}

// MARK: - Choosing between two copies

extension SudokuPlayState {
    /// Which of a locally cached grid and the server's copy to carry on from.
    ///
    /// The two disagree whenever a save did not land — a lost connection, the app killed mid-play —
    /// or when the same puzzle was touched on a second device. There is no merging two sudoku grids
    /// sensibly: a cell holds one digit, and picking per-cell would invent a board neither person
    /// ever saw.
    ///
    /// So it picks whole, on time played. `elapsed` only ever climbs, and only while someone is
    /// actually looking at the board, which makes it the closest thing to "which of these is
    /// further on". A finished grid always wins regardless — having solved it is not something to
    /// be rolled back by a device that was left open longer.
    static func furtherAlong(_ first: SudokuPlayState?, _ second: SudokuPlayState?) -> SudokuPlayState? {
        switch (first, second) {
        case (nil, nil): return nil
        case let (value?, nil): return value
        case let (nil, value?): return value
        case let (a?, b?):
            if a.isComplete != b.isComplete { return a.isComplete ? a : b }
            return a.elapsed >= b.elapsed ? a : b
        }
    }
}
