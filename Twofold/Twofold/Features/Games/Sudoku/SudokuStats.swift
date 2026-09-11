//
//  SudokuStats.swift
//  Twofold
//
//  What the two of you have done with sudoku so far, per difficulty.
//
//  Pure aggregation over solves already fetched — no network, no store — so the arithmetic that
//  decides "your best" and "who is ahead" can be tested rather than eyeballed on a screen that
//  needs two people and a finished puzzle to appear at all.
//

import Foundation

/// One finished solve, flattened out of a session/round/response triple.
struct SudokuSolve: Equatable {
    let sessionID: UUID
    let difficulty: SudokuDifficulty
    let responderID: UUID
    let elapsed: TimeInterval
}

struct SudokuStats: Equatable {
    struct Row: Equatable, Identifiable {
        let difficulty: SudokuDifficulty
        /// How many puzzles at this difficulty this player has finished. Their own count, not a
        /// shared one — a puzzle only one of them solved still took them the time it took.
        let mySolved: Int
        let partnerSolved: Int
        let myBest: TimeInterval?
        let partnerBest: TimeInterval?

        var id: SudokuDifficulty { difficulty }

        /// True when there is nothing to show but a dash on both sides — used to keep an untouched
        /// difficulty from claiming a row's worth of space it has no numbers for.
        var isEmpty: Bool { mySolved == 0 && partnerSolved == 0 }
    }

    /// Always all four, in difficulty order, whether or not they have been played — the table is a
    /// map of where you stand, and a missing Expert row reads as "no such thing" rather than
    /// "not yet".
    let rows: [Row]
    let myWins: Int
    let partnerWins: Int
    let ties: Int

    var head2HeadTotal: Int { myWins + partnerWins + ties }
    var hasAnything: Bool { rows.contains { !$0.isEmpty } }

    /// - Parameter solves: every finished solve either partner has, in any order.
    static func build(solves: [SudokuSolve], myID: UUID, partnerID: UUID) -> SudokuStats {
        let mine = solves.filter { $0.responderID == myID }
        let theirs = solves.filter { $0.responderID == partnerID }

        let rows = SudokuDifficulty.allCases.map { difficulty in
            let myAt = mine.filter { $0.difficulty == difficulty }
            let theirAt = theirs.filter { $0.difficulty == difficulty }
            return Row(
                difficulty: difficulty,
                mySolved: myAt.count,
                partnerSolved: theirAt.count,
                myBest: myAt.map(\.elapsed).min(),
                partnerBest: theirAt.map(\.elapsed).min()
            )
        }

        // Only sessions both of them finished can be compared at all — a puzzle one of them never
        // solved is not a win for the other, it is an unfinished puzzle.
        var myWins = 0, partnerWins = 0, ties = 0
        let theirsBySession = Dictionary(theirs.map { ($0.sessionID, $0) }, uniquingKeysWith: { first, _ in first })
        for solve in mine {
            guard let counterpart = theirsBySession[solve.sessionID] else { continue }
            // Decided by `SudokuComparison`, not by comparing the raw intervals here. The record
            // has to agree with what the comparison screen told them at the time — a session it
            // called a dead heat must not turn up in this tally as a win.
            let comparison = SudokuComparison(
                myElapsed: solve.elapsed, partnerElapsed: counterpart.elapsed, partnerName: ""
            )
            switch comparison.outcome {
            case .me: myWins += 1
            case .partner: partnerWins += 1
            case .tie: ties += 1
            }
        }

        return SudokuStats(rows: rows, myWins: myWins, partnerWins: partnerWins, ties: ties)
    }
}
