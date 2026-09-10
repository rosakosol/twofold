//
//  SudokuGrid.swift
//  Twofold
//
//  A 9×9 board, and the two questions worth asking of one: is this placement legal, and how many
//  ways does this puzzle finish?
//
//  Stored as a flat 81-element array rather than a 2D one. Every operation here is either "walk a
//  row, column or box" or "try a value and take it back", and both are cheaper and clearer against
//  a flat buffer — the generator solves the same grid tens of times to check uniqueness, so this is
//  the one place in the game where speed shows.
//
//  Zero means empty. Values are 1...9.
//

import Foundation

struct SudokuGrid: Equatable {
    /// Row-major, 81 cells. Index `r * 9 + c`.
    private(set) var cells: [UInt8]

    init() { cells = Array(repeating: 0, count: 81) }

    init?(cells: [UInt8]) {
        guard cells.count == 81, cells.allSatisfy({ $0 <= 9 }) else { return nil }
        self.cells = cells
    }

    subscript(index: Int) -> UInt8 {
        get { cells[index] }
        set { cells[index] = newValue }
    }

    subscript(row: Int, column: Int) -> UInt8 {
        get { cells[row * 9 + column] }
        set { cells[row * 9 + column] = newValue }
    }

    var isComplete: Bool { !cells.contains(0) }
    var givenCount: Int { cells.count { $0 != 0 } }

    /// Whether `value` may go in `index` given what is already placed.
    ///
    /// Deliberately does not look at the cell's own contents: callers ask this *before* writing,
    /// and the solver asks it about cells it is about to overwrite during backtracking.
    func canPlace(_ value: UInt8, at index: Int) -> Bool {
        guard value >= 1, value <= 9 else { return false }
        let row = index / 9
        let column = index % 9

        for c in 0..<9 where c != column {
            if cells[row * 9 + c] == value { return false }
        }
        for r in 0..<9 where r != row {
            if cells[r * 9 + column] == value { return false }
        }

        let boxRow = (row / 3) * 3
        let boxColumn = (column / 3) * 3
        for r in boxRow..<(boxRow + 3) {
            for c in boxColumn..<(boxColumn + 3) where !(r == row && c == column) {
                if cells[r * 9 + c] == value { return false }
            }
        }
        return true
    }

    /// Whether every filled cell is legal where it sits. A partially filled grid can be valid.
    var isValid: Bool {
        for index in 0..<81 where cells[index] != 0 {
            if !canPlace(cells[index], at: index) { return false }
        }
        return true
    }

    /// How many ways this grid can be completed, counted up to `limit` and no further.
    ///
    /// The generator only ever needs "exactly one, or more than one", and the costs are lopsided:
    /// finding a second solution usually happens at once, while proving there is no second means
    /// exhausting the search. So this stops as soon as the question is answered.
    func solutionCount(limit: Int = 2) -> Int {
        var solver = Solver(grid: self)
        return solver.count(limit: limit)
    }

    /// The completed grid, or nil if there is none.
    func solved() -> SudokuGrid? {
        var solver = Solver(grid: self)
        return solver.firstSolution()
    }

    // MARK: - Search

    /// The board plus a running record of what each row, column and box already holds.
    ///
    /// The masks are the whole point. Without them every step asks "what can go here" by walking 27
    /// cells per candidate per empty cell, which for a sparse grid is tens of thousands of
    /// operations per node — generating one Expert puzzle took about 1.9 seconds, long enough to
    /// stall the screen on an older phone, and Expert is a paid tier.
    ///
    /// With a bitmask per unit, "can this value go here" is one AND, and counting a cell's options
    /// is a popcount. The search itself is unchanged: same order, same answers, same puzzles for a
    /// given seed — which matters, because a faster generator that produced *different* grids would
    /// silently desync every partner mid-upgrade.
    private struct Solver {
        var cells: [UInt8]
        /// Bit `v` set means value `v` is already used in that unit. Bit 0 is unused.
        var rows = [UInt16](repeating: 0, count: 9)
        var columns = [UInt16](repeating: 0, count: 9)
        var boxes = [UInt16](repeating: 0, count: 9)

        init(grid: SudokuGrid) {
            cells = grid.cells
            for index in 0..<81 where cells[index] != 0 {
                set(cells[index], at: index)
            }
        }

        @inline(__always) private static func box(_ index: Int) -> Int {
            ((index / 9) / 3) * 3 + ((index % 9) / 3)
        }

        @inline(__always) mutating func set(_ value: UInt8, at index: Int) {
            let bit = UInt16(1) << UInt16(value)
            rows[index / 9] |= bit
            columns[index % 9] |= bit
            boxes[Self.box(index)] |= bit
        }

        @inline(__always) mutating func clear(_ value: UInt8, at index: Int) {
            let bit = UInt16(1) << UInt16(value)
            rows[index / 9] &= ~bit
            columns[index % 9] &= ~bit
            boxes[Self.box(index)] &= ~bit
        }

        /// Values still available at `index`, as bits 1...9.
        @inline(__always) func availableMask(at index: Int) -> UInt16 {
            let used = rows[index / 9] | columns[index % 9] | boxes[Self.box(index)]
            return ~used & 0b11_1111_1110
        }

        /// The empty cell with fewest options, or nil when full. Bails out immediately on a cell
        /// with none — that branch is already dead.
        func mostConstrainedEmptyCell() -> Int? {
            var best: Int?
            var bestCount = 10
            for index in 0..<81 where cells[index] == 0 {
                let count = availableMask(at: index).nonzeroBitCount
                if count == 0 { return index }
                if count < bestCount {
                    bestCount = count
                    best = index
                    if count == 1 { return index }
                }
            }
            return best
        }

        mutating func count(limit: Int) -> Int {
            var found = 0
            search(found: &found, limit: limit)
            return found
        }

        private mutating func search(found: inout Int, limit: Int) {
            guard let index = mostConstrainedEmptyCell() else {
                found += 1
                return
            }
            var mask = availableMask(at: index)
            while mask != 0 {
                let value = UInt8(mask.trailingZeroBitCount)
                mask &= mask - 1

                cells[index] = value
                set(value, at: index)
                search(found: &found, limit: limit)
                clear(value, at: index)
                cells[index] = 0

                if found >= limit { return }
            }
        }

        mutating func firstSolution() -> SudokuGrid? {
            guard let index = mostConstrainedEmptyCell() else {
                return SudokuGrid(cells: cells)
            }
            var mask = availableMask(at: index)
            while mask != 0 {
                let value = UInt8(mask.trailingZeroBitCount)
                mask &= mask - 1

                cells[index] = value
                set(value, at: index)
                if let solution = firstSolution() { return solution }
                clear(value, at: index)
                cells[index] = 0
            }
            return nil
        }
    }

}
