//
//  SudokuProgressCache.swift
//  Twofold
//
//  The half-finished grid, kept on the device.
//
//  Deliberately not `PendingGameResponseStore`. That queue appends every answer and drains them in
//  order, which is right for a game where each round's answer is its own fact. A sudoku produces a
//  new state on every single tap, all of them describing the same one round — queued, they would
//  pile up hundreds deep and then replay the puzzle keystroke by keystroke. Only the newest matters,
//  so this replaces in place.
//
//  Keyed by responder as well as session, for the reason `PendingGameResponseStore.clear()` spells
//  out: anything left here by one account would otherwise be picked up by the next person to sign
//  in on this device — here, as their half-solved puzzle.
//

import Foundation

enum SudokuProgressCache {
    private static let key = "sudokuProgress"

    private struct Entry: Codable {
        var sessionID: UUID
        var responderID: UUID
        var encoded: String
        var savedAt: Date
    }

    static func save(_ state: SudokuPlayState, sessionID: UUID, responderID: UUID) {
        var entries = all().filter { !($0.sessionID == sessionID && $0.responderID == responderID) }
        entries.append(Entry(sessionID: sessionID, responderID: responderID, encoded: state.encoded, savedAt: .now))
        write(entries)
    }

    static func load(sessionID: UUID, responderID: UUID, puzzle: SudokuGrid) -> SudokuPlayState? {
        guard let entry = all().first(where: { $0.sessionID == sessionID && $0.responderID == responderID })
        else { return nil }
        return SudokuPlayState.decoded(from: entry.encoded, puzzle: puzzle)
    }

    static func remove(sessionID: UUID, responderID: UUID) {
        write(all().filter { !($0.sessionID == sessionID && $0.responderID == responderID) })
    }

    /// Signing out takes these with it, exactly as the pending-answer queue does.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func all() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private static func write(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
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
