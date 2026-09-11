//
//  SudokuGeneratorTests.swift
//  TwofoldTests
//
//  Puzzles are generated on each device rather than fetched, so two partners must derive an
//  identical grid from the same identity without ever comparing notes. Two things have to hold, and
//  both fail silently:
//
//    * The same seed gives the same puzzle — on every device, and after every future change to this
//      code. Break it and two people on different app versions solve different grids and compare
//      results that mean nothing. Nothing crashes.
//    * Every puzzle has exactly one solution. A grid with two is not hard, it is broken: a player
//      fills it in correctly and is told they are wrong.
//

import Testing
import Foundation
@testable import Twofold

struct SudokuGeneratorTests {

    // MARK: - The compatibility contract

    /// A known seed against a known grid, written out in full.
    ///
    /// This is not a unit test so much as a version-to-version contract, and it is meant to be
    /// annoying to change. If it fails, something altered the generator's arithmetic — a constant in
    /// `PuzzleRandom`, the shuffle, the order cells are carved — and every partner on a different
    /// app version is now solving a different puzzle from the person next to them.
    ///
    /// Updating the expected string to make it pass is almost always the wrong fix. The right one is
    /// to put back whatever changed, or to accept the break deliberately and ship both versions at
    /// once.
    @Test("a known seed produces a known puzzle")
    func knownSeedProducesKnownPuzzle() {
        let produced = SudokuGenerator.puzzle(seed: 12_345, difficulty: .medium)
        let asString = produced.puzzle.cells.map(String.init).joined()

        // Captured from this implementation. See the note above before touching it.
        let expected = SudokuGeneratorTests.knownMediumPuzzle
        #expect(asString == expected, """
            The generator no longer produces the same puzzle for seed 12345.
            Two partners on different app versions would now solve different grids.
            got:      \(asString)
            expected: \(expected)
            """)
    }

    /// The same property stated the way it is actually relied on: two devices, one identity.
    @Test("the same identity gives the same puzzle every time")
    func sameIdentitySamePuzzle() {
        let id = UUID(uuidString: "5A1E6C7E-0000-0000-0000-00000000000A")!
        let first = SudokuGenerator.puzzle(for: id, difficulty: .hard)
        let second = SudokuGenerator.puzzle(for: id, difficulty: .hard)
        #expect(first == second)
    }

    /// And that it is the identity doing the work, not chance agreeing twice.
    @Test("different identities give different puzzles")
    func differentIdentitiesDiffer() {
        let a = SudokuGenerator.puzzle(for: UUID(), difficulty: .medium)
        let b = SudokuGenerator.puzzle(for: UUID(), difficulty: .medium)
        #expect(a.puzzle != b.puzzle)
    }

    /// Difficulty is part of the identity too. The same round at two difficulties is two puzzles.
    @Test("difficulty changes the puzzle")
    func difficultyChangesThePuzzle() {
        let id = UUID(uuidString: "5A1E6C7E-0000-0000-0000-00000000000B")!
        #expect(SudokuGenerator.puzzle(for: id, difficulty: .easy).puzzle
                != SudokuGenerator.puzzle(for: id, difficulty: .expert).puzzle)
    }

    // MARK: - The puzzles are actually solvable, once

    /// The property that makes a puzzle a puzzle. Checked across every difficulty and several
    /// seeds, because a generator that usually produces unique puzzles is not good enough — the
    /// player who hits the exception is told their correct answer is wrong.
    @Test("every generated puzzle has exactly one solution", arguments: SudokuDifficulty.allCases)
    func exactlyOneSolution(difficulty: SudokuDifficulty) {
        for seed in UInt64(1)...UInt64(6) {
            let generated = SudokuGenerator.puzzle(seed: seed, difficulty: difficulty)
            #expect(generated.puzzle.solutionCount(limit: 2) == 1,
                    "\(difficulty) seed \(seed) is ambiguous or unsolvable")
        }
    }

    /// And that the solution handed back is the one it solves to, rather than a grid built
    /// alongside it that happens to look right.
    @Test("the stored solution is the puzzle's own solution", arguments: SudokuDifficulty.allCases)
    func solutionMatches(difficulty: SudokuDifficulty) {
        let generated = SudokuGenerator.puzzle(seed: 99, difficulty: difficulty)
        #expect(generated.solution.isComplete)
        #expect(generated.solution.isValid)
        #expect(generated.puzzle.solved() == generated.solution)
    }

    /// Every given must agree with the solution — an inconsistency here would be unnoticeable until
    /// a player tried to finish.
    @Test("the givens are a subset of the solution")
    func givensMatchSolution() {
        let generated = SudokuGenerator.puzzle(seed: 7, difficulty: .hard)
        for index in 0..<81 where generated.puzzle[index] != 0 {
            #expect(generated.puzzle[index] == generated.solution[index], "cell \(index) contradicts the solution")
        }
    }

    // MARK: - Difficulty means something

    /// The floor is the promise; puzzles may land above it when removal cannot go further without
    /// making the grid ambiguous. What must never happen is landing *below* it.
    @Test("each difficulty respects its floor", arguments: SudokuDifficulty.allCases)
    func respectsFloor(difficulty: SudokuDifficulty) {
        for seed in UInt64(1)...UInt64(4) {
            let count = SudokuGenerator.puzzle(seed: seed, difficulty: difficulty).puzzle.givenCount
            #expect(count >= difficulty.givenRange.lowerBound,
                    "\(difficulty) seed \(seed) gave \(count), under its floor of \(difficulty.givenRange.lowerBound)")
        }
    }

    /// And that the difficulties are ordered — an Expert with more numbers showing than an Easy
    /// would be a labelling bug nobody would report, they would just find Expert easy.
    @Test("harder difficulties show fewer numbers")
    func difficultiesAreOrdered() {
        func averageGivens(_ difficulty: SudokuDifficulty) -> Double {
            let counts = (UInt64(1)...UInt64(4)).map {
                Double(SudokuGenerator.puzzle(seed: $0, difficulty: difficulty).puzzle.givenCount)
            }
            return counts.reduce(0, +) / Double(counts.count)
        }
        let easy = averageGivens(.easy)
        let medium = averageGivens(.medium)
        let hard = averageGivens(.hard)
        let expert = averageGivens(.expert)
        #expect(easy > medium, "easy \(easy) should show more than medium \(medium)")
        #expect(medium > hard, "medium \(medium) should show more than hard \(hard)")
        #expect(hard > expert, "hard \(hard) should show more than expert \(expert)")
    }

    // MARK: - The generator's own RNG

    /// The shuffle is written out rather than taken from the standard library precisely so this can
    /// be true across Swift versions. Same seed, same permutation.
    @Test("the shuffle is reproducible")
    func shuffleIsReproducible() {
        var a = PuzzleRandom(seed: 42)
        var b = PuzzleRandom(seed: 42)
        let items = Array(0..<20)
        #expect(a.shuffled(items) == b.shuffled(items))
    }

    /// A shuffle that returned the input unchanged would still pass the test above.
    @Test("the shuffle actually shuffles")
    func shuffleActuallyShuffles() {
        var random = PuzzleRandom(seed: 42)
        let items = Array(0..<20)
        let shuffled = random.shuffled(items)
        #expect(shuffled != items)
        #expect(shuffled.sorted() == items, "a shuffle must not lose or invent elements")
    }

    /// Bounds are respected, including the degenerate one.
    @Test("bounded draws stay in range")
    func boundedDrawsStayInRange() {
        var random = PuzzleRandom(seed: 3)
        for _ in 0..<500 {
            let value = random.next(upperBound: 9)
            #expect(value >= 0 && value < 9)
        }
        #expect(random.next(upperBound: 1) == 0)
    }
}

// MARK: - Fixture

extension SudokuGeneratorTests {
    /// Seed 12345 at Medium, as this generator produces it. 81 digits, row-major, 0 for empty.
    ///
    /// Captured once and then left alone. It survived the switch to bitmask propagation unchanged,
    /// which is exactly the reassurance it exists to give: that optimisation made generation 27
    /// times faster and, had it altered the search order by accident, would have handed two
    /// partners on either side of the update different puzzles with nothing failing.
    static let knownMediumPuzzle =
        "090083016857090000000002000160040090408270001002610300700000000040867020680924000"
}
