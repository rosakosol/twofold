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
    /// How many cells were filled in by asking, and how many times the board was checked against
    /// the solution.
    ///
    /// Counted because the comparison screen puts two times side by side and calls one of them
    /// faster. A solve with four hints in it is not the same achievement as one without, and a
    /// race where that difference is invisible is not a race — it just rewards whoever was most
    /// willing to ask. Counts only: which cells were hinted is not worth the payload, since nothing
    /// needs to undo or re-show them.
    private(set) var hintsUsed: Int
    private(set) var checksUsed: Int

    init(puzzle: SudokuGrid) {
        entries = puzzle.cells
        notes = Array(repeating: 0, count: 81)
        elapsed = 0
        isComplete = false
        hintsUsed = 0
        checksUsed = 0
    }

    private init(
        entries: [UInt8],
        notes: [UInt16],
        elapsed: TimeInterval,
        isComplete: Bool,
        hintsUsed: Int,
        checksUsed: Int
    ) {
        self.entries = entries
        self.notes = notes
        self.elapsed = elapsed
        self.isComplete = isComplete
        self.hintsUsed = hintsUsed
        self.checksUsed = checksUsed
    }

    /// Unassisted — nothing was revealed and nothing was checked.
    var isUnaided: Bool { hintsUsed == 0 && checksUsed == 0 }

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

    /// Entries that disagree with the solution.
    ///
    /// Distinct from `conflicts()`, which only catches a digit repeated against one of its peers.
    /// A wrong digit that happens to break no rule yet is invisible to that — and it is the worst
    /// kind, because the board looks fine until the grid is full and nothing fits. This is the only
    /// thing that can see it, and the only thing that needs the solution to do so.
    func mistakes(solution: SudokuGrid) -> Set<Int> {
        var found: Set<Int> = []
        for index in 0..<81 where entries[index] != 0 && entries[index] != solution[index] {
            found.insert(index)
        }
        return found
    }

    // MARK: - Asking for help

    /// Writes the solution's digit into one cell and counts it.
    ///
    /// Takes the index rather than choosing one, so the caller decides what a hint means — see
    /// `SudokuGameStore.useHint()`, which prefers the selected cell and otherwise picks for them.
    mutating func revealCell(at index: Int, solution: SudokuGrid, puzzle: SudokuGrid) {
        guard (0..<81).contains(index), !puzzle.isGiven(index) else { return }
        place(solution[index], at: index, puzzle: puzzle)
        hintsUsed += 1
    }

    /// Counts a look at the solution. The cells it turns up are the caller's to show; only the fact
    /// that it was asked is recorded, because that is what the comparison has to be honest about.
    mutating func recordCheck() {
        checksUsed += 1
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
    /// `sudoku.v2|<81 digits>|<81 x 3 hex>|<elapsed seconds>|<0 or 1>|<hints>|<checks>`
    ///
    /// Fixed-width fields and a leading version, so a future change to the shape is a new version
    /// rather than a guess about which format a given string is in.
    ///
    /// v1 was the same without the last two fields, and is still read — every puzzle solved before
    /// hints existed is a v1 row sitting in `game_responses`, and those are exactly the rows the
    /// stats table and the resume path depend on. A v1 payload decodes as a solve with no hints and
    /// no checks, which is true of it: there was no way to use either.
    ///
    /// Everything is written as v2 from here. That is deliberate rather than writing whichever
    /// version a state came from — two live formats is the thing that eventually gets read wrong,
    /// and an old device reading a v2 refuses it outright (see `decoded`) rather than
    /// misinterpreting it.
    private static let version2 = "sudoku.v2"
    private static let version1 = "sudoku.v1"

    var encoded: String {
        let grid = entries.map(String.init).joined()
        let marks = notes.map { String(format: "%03x", $0) }.joined()
        return [
            Self.version2,
            grid,
            marks,
            String(Int(elapsed.rounded())),
            isComplete ? "1" : "0",
            String(hintsUsed),
            String(checksUsed)
        ].joined(separator: "|")
    }

    /// Just the time and whether it was finished, for a caller that has the string but not the
    /// puzzle it belongs to.
    ///
    /// `decoded` needs a `SudokuGrid` only to re-impose the givens on the entries it read — which
    /// is the right thing when the grid is going back on screen, and pure waste for stats, where
    /// every row would mean generating a whole puzzle to reach two fields at the end of the string.
    ///
    /// Deliberately as strict as `decoded` about the version and the field count, so a `sudoku.v2`
    /// is refused here too rather than being read as a v1 that happens to start the same way. The
    /// two are pinned to each other by test.
    static func summary(from string: String) -> (elapsed: TimeInterval, isComplete: Bool, hintsUsed: Int, checksUsed: Int)? {
        let fields = string.split(separator: "|", omittingEmptySubsequences: false)
        guard let shape = Shape(fields: fields) else { return nil }
        guard let seconds = Int(fields[3]), seconds >= 0 else { return nil }
        guard fields[4] == "0" || fields[4] == "1" else { return nil }
        guard let aids = shape.aids(in: fields) else { return nil }
        return (TimeInterval(seconds), fields[4] == "1", aids.hints, aids.checks)
    }

    /// Which version a payload claims, and what that implies about its shape. Both readers go
    /// through this so neither can quietly start accepting a field count the other refuses.
    private enum Shape {
        case v1
        case v2

        init?(fields: [Substring]) {
            guard let version = fields.first else { return nil }
            switch (version, fields.count) {
            case (Substring(SudokuPlayState.version1), 5): self = .v1
            case (Substring(SudokuPlayState.version2), 7): self = .v2
            default: return nil
            }
        }

        /// The two counters, or zero for a payload written before either existed. Nil when the
        /// fields are present but unreadable — a negative count, or something that isn't a number.
        func aids(in fields: [Substring]) -> (hints: Int, checks: Int)? {
            switch self {
            case .v1:
                return (0, 0)
            case .v2:
                guard let hints = Int(fields[5]), hints >= 0,
                      let checks = Int(fields[6]), checks >= 0
                else { return nil }
                return (hints, checks)
            }
        }
    }

    /// Reads a state back, or gives up.
    ///
    /// `puzzle` is not decoration. The stored grid is whatever was last written, and the givens are
    /// re-imposed on top of it here — so a payload that has been truncated, tampered with, or
    /// written against a *different* puzzle can never present one of this puzzle's own numbers as
    /// missing or changed. The player's own entries are the only part the string gets to decide.
    static func decoded(from string: String, puzzle: SudokuGrid) -> SudokuPlayState? {
        let fields = string.split(separator: "|", omittingEmptySubsequences: false)
        guard let shape = Shape(fields: fields) else { return nil }

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
        guard let aids = shape.aids(in: fields) else { return nil }

        // The givens win, always.
        for index in 0..<81 where puzzle.isGiven(index) {
            entries[index] = puzzle[index]
            notes[index] = 0
        }

        return SudokuPlayState(
            entries: entries,
            notes: notes,
            elapsed: TimeInterval(seconds),
            isComplete: fields[4] == "1",
            hintsUsed: aids.hints,
            checksUsed: aids.checks
        )
    }
}

private extension SudokuGrid {
    func isGiven(_ index: Int) -> Bool { self[index] != 0 }
}
