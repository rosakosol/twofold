//
//  SudokuPlayState.swift
//  Twofold
//
//  A half-finished sudoku, in a form that survives the app being killed and reopened on another
//  device.
//
//  This rides in `game_responses.answer` as a single string, through the same
//  `GameAnswerPayload` every other game uses. That is not a workaround: a sudoku's answer really
//  is one value — the grid as it stands, how long it took, and whether it is finished — so
//  nothing here needed a new column, a new table or a per-game payload shape.
//
//  The encoding is versioned and parsed strictly. Anything it cannot read it refuses, and the
//  caller starts the puzzle fresh rather than showing a grid built out of a half-understood
//  string; a sudoku restored wrong is worse than a sudoku restored not at all, because the player
//  cannot tell.
//

import Foundation

struct SudokuPlayState: Equatable {
    /// The whole grid as it currently stands, givens included. 0 is empty.
    private(set) var entries: [UInt8]
    /// Pencil marks per cell. Bit `v` set means the player wrote a small `v` there. Bit 0 unused,
    /// matching `SudokuGrid`'s solver masks.
    private(set) var notes: [UInt16]
    /// Seconds of play. Held here rather than derived from timestamps because the clock only runs
    /// while the board is on screen — a puzzle left open overnight has not been played overnight.
    var elapsed: TimeInterval
    private(set) var isComplete: Bool

    init(puzzle: SudokuGrid) {
        entries = puzzle.cells
        notes = Array(repeating: 0, count: 81)
        elapsed = 0
        isComplete = false
    }

    private init(entries: [UInt8], notes: [UInt16], elapsed: TimeInterval, isComplete: Bool) {
        self.entries = entries
        self.notes = notes
        self.elapsed = elapsed
        self.isComplete = isComplete
    }

    subscript(index: Int) -> UInt8 { entries[index] }

    func note(_ value: UInt8, at index: Int) -> Bool {
        guard value >= 1, value <= 9 else { return false }
        return notes[index] & (UInt16(1) << UInt16(value)) != 0
    }

    var filledCount: Int { entries.count { $0 != 0 } }

    // MARK: - Playing

    /// Writes a digit, unless the cell is one of the puzzle's own.
    ///
    /// Also rubs that digit out of the pencil marks of every cell that can now no longer hold it.
    /// Doing it by hand is the tedious part of playing on paper, and leaving a stale note behind is
    /// worse than useless — it is a note that says a cell can take a digit the board has already
    /// ruled out.
    mutating func place(_ value: UInt8, at index: Int, puzzle: SudokuGrid) {
        guard (1...9).contains(value), !puzzle.isGiven(index) else { return }
        entries[index] = value
        notes[index] = 0

        let bit = ~(UInt16(1) << UInt16(value))
        for peer in Self.peers(of: index) {
            notes[peer] &= bit
        }
    }

    mutating func erase(at index: Int, puzzle: SudokuGrid) {
        guard !puzzle.isGiven(index) else { return }
        entries[index] = 0
        notes[index] = 0
    }

    /// Pencil marks are only meaningful on an empty cell, so writing one clears any digit there.
    mutating func toggleNote(_ value: UInt8, at index: Int, puzzle: SudokuGrid) {
        guard (1...9).contains(value), !puzzle.isGiven(index) else { return }
        entries[index] = 0
        notes[index] ^= UInt16(1) << UInt16(value)
    }

    mutating func markComplete() { isComplete = true }

    // MARK: - What the board shows

    /// Cells holding a digit that repeats somewhere it shares a row, column or box with.
    ///
    /// Both offenders are returned, not just the later one — the player needs to see the pair to
    /// know which to change, and highlighting only one implies the other is right.
    ///
    /// A given can appear here. It cannot itself be wrong, but a wrong entry conflicting with it
    /// should light the pair up, or the highlight looks like it has missed something.
    func conflicts() -> Set<Int> {
        var found: Set<Int> = []
        for index in 0..<81 where entries[index] != 0 {
            for peer in Self.peers(of: index) where entries[peer] == entries[index] {
                found.insert(index)
                found.insert(peer)
            }
        }
        return found
    }

    /// Finished and correct. Checked against the solution rather than against the rules, because a
    /// full grid that breaks no rule *is* the solution — there is only one — so this is the same
    /// answer arrived at more cheaply.
    func isSolved(solution: SudokuGrid) -> Bool {
        entries == solution.cells
    }

    /// The cells this one shares a row, column or box with. Never includes itself.
    static func peers(of index: Int) -> [Int] {
        precondition((0..<81).contains(index))
        return peerTable[index]
    }

    private static let peerTable: [[Int]] = (0..<81).map { index in
        let row = index / 9, column = index % 9
        let boxRow = (row / 3) * 3, boxColumn = (column / 3) * 3
        var peers = Set<Int>()
        for c in 0..<9 { peers.insert(row * 9 + c) }
        for r in 0..<9 { peers.insert(r * 9 + column) }
        for r in boxRow..<(boxRow + 3) {
            for c in boxColumn..<(boxColumn + 3) { peers.insert(r * 9 + c) }
        }
        peers.remove(index)
        return peers.sorted()
    }
}

// MARK: - Persistence

extension SudokuPlayState {
    /// `sudoku.v1|<81 digits>|<81 x 3 hex>|<elapsed seconds>|<0 or 1>`
    ///
    /// Fixed-width fields and a leading version, so a future change to the shape is a new version
    /// rather than a guess about which format a given string is in.
    private static let version = "sudoku.v1"

    var encoded: String {
        let grid = entries.map(String.init).joined()
        let marks = notes.map { String(format: "%03x", $0) }.joined()
        return [
            Self.version,
            grid,
            marks,
            String(Int(elapsed.rounded())),
            isComplete ? "1" : "0"
        ].joined(separator: "|")
    }

    /// Reads a state back, or gives up.
    ///
    /// `puzzle` is not decoration. The stored grid is whatever was last written, and the givens are
    /// re-imposed on top of it here — so a payload that has been truncated, tampered with, or
    /// written against a *different* puzzle can never present one of this puzzle's own numbers as
    /// missing or changed. The player's own entries are the only part the string gets to decide.
    static func decoded(from string: String, puzzle: SudokuGrid) -> SudokuPlayState? {
        let fields = string.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 5, fields[0] == version else { return nil }

        let gridField = fields[1]
        guard gridField.count == 81 else { return nil }
        var entries = [UInt8]()
        entries.reserveCapacity(81)
        for character in gridField {
            guard let digit = character.wholeNumberValue, (0...9).contains(digit) else { return nil }
            entries.append(UInt8(digit))
        }

        let marksField = fields[2]
        guard marksField.count == 243 else { return nil }
        var notes = [UInt16]()
        notes.reserveCapacity(81)
        var cursor = marksField.startIndex
        for _ in 0..<81 {
            let end = marksField.index(cursor, offsetBy: 3)
            guard let mask = UInt16(marksField[cursor..<end], radix: 16) else { return nil }
            // Bit 0 and bits above 9 are not writable through `toggleNote`, so their presence means
            // this string did not come from here.
            guard mask & ~0b11_1111_1110 == 0 else { return nil }
            notes.append(mask)
            cursor = end
        }

        guard let seconds = Int(fields[3]), seconds >= 0 else { return nil }
        guard fields[4] == "0" || fields[4] == "1" else { return nil }

        // The givens win, always.
        for index in 0..<81 where puzzle.isGiven(index) {
            entries[index] = puzzle[index]
            notes[index] = 0
        }

        return SudokuPlayState(
            entries: entries,
            notes: notes,
            elapsed: TimeInterval(seconds),
            isComplete: fields[4] == "1"
        )
    }
}

private extension SudokuGrid {
    func isGiven(_ index: Int) -> Bool { self[index] != 0 }
}
