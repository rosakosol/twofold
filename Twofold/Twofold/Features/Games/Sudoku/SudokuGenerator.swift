//
//  SudokuGenerator.swift
//  Twofold
//
//  Turning a puzzle's identity into the puzzle itself.
//
//  Both partners hold the same `content_id` for a round and derive the grid from it here, so the
//  puzzle never travels — it is regenerated on each device from 128 bits. That is what lets a game
//  start offline, and it is why every step below is deterministic given the seed.
//
//  Two properties matter more than anything else about the puzzles themselves:
//
//    1. The same seed always gives the same puzzle. Not just today, but after a Swift upgrade and a
//       year of refactors — otherwise two partners on different app versions solve different grids
//       and compare nonsense. `PuzzleRandom` carries most of that weight.
//    2. Every puzzle has exactly one solution. A grid with two is not a hard sudoku, it is a broken
//       one: a player fills it in correctly and is told they are wrong.
//

import Foundation

enum SudokuDifficulty: String, CaseIterable, Codable, Sendable {
    case easy, medium, hard, expert

    /// How many numbers are showing at the start.
    ///
    /// A range rather than a number because removal stops when it can no longer keep the solution
    /// unique, and forcing an exact count would mean either rejecting good puzzles or accepting
    /// ambiguous ones. The floor is what the difficulty promises; the ceiling is where removal
    /// starts giving up.
    ///
    /// 17 is the proven minimum for any uniquely-solvable sudoku, so Expert sits just above it and
    /// will often land higher — that is the algorithm being honest rather than falling short.
    var givenRange: ClosedRange<Int> {
        switch self {
        case .easy: 44...50
        case .medium: 34...40
        case .hard: 28...32
        case .expert: 22...26
        }
    }

    var displayName: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        case .expert: "Expert"
        }
    }
}

struct SudokuPuzzle: Equatable {
    /// What the player starts with. Zero is an empty cell.
    let puzzle: SudokuGrid
    /// The one grid it completes to. Held so a solve can be marked without searching again.
    let solution: SudokuGrid
    let difficulty: SudokuDifficulty

    /// Cells the player may not change.
    func isGiven(_ index: Int) -> Bool { puzzle[index] != 0 }
}

enum SudokuGenerator {

    /// The puzzle for this identity. Same id, same difficulty, same grid — always.
    static func puzzle(for id: UUID, difficulty: SudokuDifficulty) -> SudokuPuzzle {
        var random = PuzzleRandom(puzzleID: id)
        return generate(using: &random, difficulty: difficulty)
    }

    /// Seed-based entry point, for tests and for anywhere an identity is not a UUID.
    static func puzzle(seed: UInt64, difficulty: SudokuDifficulty) -> SudokuPuzzle {
        var random = PuzzleRandom(seed: seed)
        return generate(using: &random, difficulty: difficulty)
    }

    // MARK: -

    private static func generate(using random: inout PuzzleRandom, difficulty: SudokuDifficulty) -> SudokuPuzzle {
        let solution = completedGrid(using: &random)
        let puzzle = carve(from: solution, using: &random, difficulty: difficulty)
        return SudokuPuzzle(puzzle: puzzle, solution: solution, difficulty: difficulty)
    }

    /// A full, legal grid, built by filling cells in order and trying values in a shuffled order.
    ///
    /// The shuffle is the only source of variety — the search itself is plain backtracking — and it
    /// is what makes the seed decide the whole grid.
    private static func completedGrid(using random: inout PuzzleRandom) -> SudokuGrid {
        var grid = SudokuGrid()
        _ = fill(&grid, from: 0, using: &random)
        return grid
    }

    private static func fill(_ grid: inout SudokuGrid, from index: Int, using random: inout PuzzleRandom) -> Bool {
        guard index < 81 else { return true }
        guard grid[index] == 0 else { return fill(&grid, from: index + 1, using: &random) }

        for value in random.shuffled(Array(UInt8(1)...UInt8(9))) where grid.canPlace(value, at: index) {
            grid[index] = value
            if fill(&grid, from: index + 1, using: &random) { return true }
            grid[index] = 0
        }
        return false
    }

    /// Removes numbers one at a time, keeping the solution unique, until the target is reached.
    ///
    /// Each candidate removal is tried and then checked: if the grid now has more than one
    /// solution, the number goes back. That check is the expensive part of generation and the
    /// reason `solutionCount` stops at two.
    ///
    /// Cells are visited in a shuffled order rather than swept, so two puzzles of the same
    /// difficulty do not share a shape. Removal stops at the floor of the range or when every
    /// remaining cell has been tried — whichever comes first, which is why the range has a ceiling.
    private static func carve(
        from solution: SudokuGrid,
        using random: inout PuzzleRandom,
        difficulty: SudokuDifficulty
    ) -> SudokuGrid {
        var puzzle = solution
        let target = difficulty.givenRange.lowerBound

        for index in random.shuffled(Array(0..<81)) {
            if puzzle.givenCount <= target { break }
            let removed = puzzle[index]
            guard removed != 0 else { continue }

            puzzle[index] = 0
            if puzzle.solutionCount(limit: 2) != 1 {
                puzzle[index] = removed
            }
        }
        return puzzle
    }
}
