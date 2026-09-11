//
//  SudokuStatsTests.swift
//  TwofoldTests
//
//  The stats table is the one screen in sudoku that cannot be checked by playing: it needs a
//  history of finished puzzles across two people and four difficulties to say anything at all. So
//  the arithmetic is pinned here instead — and the ways it goes wrong are all silent:
//
//    * A puzzle only one of them finished counting as a win for the other, which inflates a record
//      out of games that were never a contest.
//    * The record disagreeing with what the comparison screen said at the time — a dead heat shown
//      on the day, tallied later as a win.
//    * A best time taken across difficulties, so an Easy solve becomes somebody's Expert record.
//

import Testing
import Foundation
@testable import Twofold

struct SudokuStatsTests {
    private let me = UUID()
    private let partner = UUID()

    private func solve(
        _ session: UUID, _ difficulty: SudokuDifficulty, _ who: UUID, _ elapsed: TimeInterval
    ) -> SudokuSolve {
        SudokuSolve(sessionID: session, difficulty: difficulty, responderID: who, elapsed: elapsed)
    }

    private func build(_ solves: [SudokuSolve]) -> SudokuStats {
        SudokuStats.build(solves: solves, myID: me, partnerID: partner)
    }

    // MARK: - Shape

    @Test("all four difficulties are present even with no history at all")
    func emptyStillHasEveryRow() {
        let stats = build([])
        #expect(stats.rows.map(\.difficulty) == SudokuDifficulty.allCases)
        #expect(stats.rows.map(\.isEmpty) == [true, true, true, true])
        #expect(stats.hasAnything == false)
        #expect(stats.head2HeadTotal == 0)
    }

    // MARK: - Best times

    @Test("a best time is the quickest at that difficulty, and only that difficulty")
    func bestIsPerDifficulty() throws {
        let a = UUID(), b = UUID()
        let stats = build([
            solve(a, .easy, me, 200),
            solve(b, .easy, me, 150),
            solve(UUID(), .expert, me, 900),
        ])
        let easy = try #require(stats.rows.first { $0.difficulty == .easy })
        let expert = try #require(stats.rows.first { $0.difficulty == .expert })
        #expect(easy.myBest == 150)
        #expect(easy.mySolved == 2)
        // The 150 from Easy must not leak into Expert's record.
        #expect(expert.myBest == 900)
        #expect(expert.mySolved == 1)
    }

    @Test("each side keeps its own best and its own count")
    func bestsAreIndependent() throws {
        let session = UUID()
        let stats = build([solve(session, .hard, me, 500), solve(session, .hard, partner, 320)])
        let hard = try #require(stats.rows.first { $0.difficulty == .hard })
        #expect(hard.myBest == 500)
        #expect(hard.partnerBest == 320)
        #expect(hard.mySolved == 1)
        #expect(hard.partnerSolved == 1)
    }

    @Test("a difficulty only one of them has played is not empty")
    func oneSidedDifficultyStillShows() throws {
        let stats = build([solve(UUID(), .medium, me, 400)])
        let medium = try #require(stats.rows.first { $0.difficulty == .medium })
        #expect(medium.isEmpty == false)
        #expect(medium.partnerBest == nil)
        #expect(medium.partnerSolved == 0)
    }

    // MARK: - The record

    @Test("the record counts only puzzles both of them finished")
    func unfinishedPuzzlesAreNotWins() {
        let shared = UUID()
        let stats = build([
            solve(shared, .medium, me, 300),
            solve(shared, .medium, partner, 420),
            // Three of mine they never finished. Solo solves, not a 4-0 lead.
            solve(UUID(), .medium, me, 100),
            solve(UUID(), .medium, me, 110),
            solve(UUID(), .easy, me, 120),
        ])
        #expect(stats.myWins == 1)
        #expect(stats.partnerWins == 0)
        #expect(stats.head2HeadTotal == 1)
        // Still counted as solves, just not as contests.
        #expect(stats.rows.first { $0.difficulty == .medium }?.mySolved == 3)
    }

    @Test("wins go to whoever was quicker, on both sides")
    func winsGoToTheQuicker() {
        let a = UUID(), b = UUID()
        let stats = build([
            solve(a, .easy, me, 100), solve(a, .easy, partner, 200),
            solve(b, .hard, me, 900), solve(b, .hard, partner, 400),
        ])
        #expect(stats.myWins == 1)
        #expect(stats.partnerWins == 1)
        #expect(stats.ties == 0)
    }

    /// The tally has to agree with the verdict shown on the day. `SudokuComparison` truncates to
    /// whole seconds because that is what the clocks displayed, so two solves a fraction apart were
    /// called a dead heat — and must not resurface here as somebody's win.
    @Test("a dead heat on the day is a draw in the record, not a win")
    func tiesMatchTheComparisonScreen() {
        let session = UUID()
        let stats = build([
            solve(session, .easy, me, 134.2),
            solve(session, .easy, partner, 134.4),
        ])
        #expect(stats.ties == 1)
        #expect(stats.myWins == 0)
        #expect(stats.partnerWins == 0)

        // The same two numbers, through the screen that announced the result at the time.
        let shown = SudokuComparison(myElapsed: 134.2, partnerElapsed: 134.4, partnerName: "Erin")
        #expect(shown.outcome == .tie)
    }
}
