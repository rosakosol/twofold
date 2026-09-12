//
//  WordSearchGeneratorTests.swift
//  TwofoldTests
//
//  That a grid is always playable, and always the same on both phones.
//
//  Two failures matter here and neither is visible from looking at one grid:
//
//    * A grid that places only seven of its eight words. The board looks fine, the list has eight
//      entries, and one of them can never be found — so the puzzle cannot be completed, the session
//      never finishes, and the partner waits forever on someone who is still looking.
//    * A grid that differs between the two partners. Both believe they are hunting the same letters
//      and their times are compared as if they were.
//

import Foundation
import Testing
@testable import Twofold

struct WordSearchGeneratorTests {

    // MARK: - Every grid is completable

    @Test("every theme places all eight words, for many seeds", arguments: WordSearchTheme.allCases)
    func alwaysPlacesEveryWord(theme: WordSearchTheme) {
        // Not one grid but two hundred. Packing eight words into a hundred cells succeeds almost
        // always, and "almost" is the whole problem: a one-in-fifty failure ships and then strands
        // whoever draws it.
        for seed in 0..<200 {
            let puzzle = WordSearchGenerator.puzzle(seed: UInt64(seed), theme: theme)
            #expect(
                puzzle.placements.count == WordSearchPuzzle.wordCount,
                "\(theme.rawValue) seed \(seed) placed \(puzzle.placements.count) words"
            )
        }
    }

    @Test("every placed word is actually readable off the grid", arguments: WordSearchTheme.allCases)
    func placedWordsAreOnTheGrid(theme: WordSearchTheme) {
        // The placement says where a word is. This checks the letters really are there — a
        // generator that recorded a placement it then overwrote would produce a list entry that
        // cannot be found, which looks identical to the player being bad at word searches.
        for seed in 0..<50 {
            let puzzle = WordSearchGenerator.puzzle(seed: UInt64(seed), theme: theme)
            for placement in puzzle.placements {
                let spelled = String(placement.cells(size: WordSearchPuzzle.size).map { puzzle[$0] })
                #expect(spelled == placement.word, "\(theme.rawValue) seed \(seed): grid spells \(spelled), placement says \(placement.word)")
            }
        }
    }

    @Test("every cell is filled and every word is distinct", arguments: WordSearchTheme.allCases)
    func gridIsComplete(theme: WordSearchTheme) {
        let puzzle = WordSearchGenerator.puzzle(seed: 7, theme: theme)
        #expect(puzzle.letters.count == WordSearchPuzzle.size * WordSearchPuzzle.size)
        #expect(!puzzle.letters.contains(" "), "a blank cell is a hole in the grid")
        #expect(puzzle.letters.allSatisfy { $0.isUppercase && $0.isLetter })
        #expect(Set(puzzle.words).count == puzzle.words.count, "the same word twice gives the list a duplicate row")
    }

    @Test("placements stay inside the grid", arguments: WordSearchTheme.allCases)
    func placementsStayInBounds(theme: WordSearchTheme) {
        let size = WordSearchPuzzle.size
        for seed in 0..<50 {
            let puzzle = WordSearchGenerator.puzzle(seed: UInt64(seed), theme: theme)
            for placement in puzzle.placements {
                let cells = placement.cells(size: size)
                #expect(cells.allSatisfy { (0..<(size * size)).contains($0) })
                // A word that wrapped from one row to the next would still be "in bounds" by index
                // while being nonsense on screen, so the step between cells is checked too.
                for (a, b) in zip(cells, cells.dropFirst()) {
                    let rowStep = abs(b / size - a / size)
                    let columnStep = abs(b % size - a % size)
                    #expect(rowStep <= 1 && columnStep <= 1, "\(placement.word) jumps across the grid")
                }
            }
        }
    }

    // MARK: - Both partners get the same grid

    @Test func theSamePuzzleIdAlwaysGivesTheSameGrid() {
        let id = UUID(uuidString: "1A2B3C4D-5E6F-7081-9203-A4B5C6D7E8F9")!
        let first = WordSearchGenerator.puzzle(for: id, theme: .travel)
        let second = WordSearchGenerator.puzzle(for: id, theme: .travel)
        #expect(first.letters == second.letters)
        #expect(first.placements == second.placements)
    }

    @Test func differentIdsGiveDifferentGrids() {
        // Not a distribution test — enough to catch a derivation that ignores the id and hands
        // everybody the same puzzle forever.
        let grids = Set((0..<50).map { String(WordSearchGenerator.puzzle(seed: UInt64($0), theme: .travel).letters) })
        #expect(grids.count > 40, "50 seeds produced only \(grids.count) distinct grids")
    }

    @Test func theThemeChangesTheGrid() {
        let travel = WordSearchGenerator.puzzle(seed: 1, theme: .travel)
        let love = WordSearchGenerator.puzzle(seed: 1, theme: .love)
        #expect(travel.letters != love.letters)
        #expect(travel.theme == .travel)
        #expect(love.theme == .love)
    }

    // MARK: - The compatibility contract

    @Test("the word lists have not moved", arguments: [
        (WordSearchTheme.travel, 18),
        (.love, 17),
        (.food, 18),
        (.nature, 18),
        (.cities, 18),
        (.music, 18),
    ])
    func wordListsArePinned(theme: WordSearchTheme, count: Int) {
        // The seeded shuffle means a list's *order* decides which eight words a grid hides.
        // Inserting one in the middle changes every grid in play, so a change here is a
        // compatibility break rather than a content edit — append only.
        #expect(theme.words.count == count)
        #expect(theme.words.allSatisfy { $0.count >= 4 && $0.count <= WordSearchPuzzle.size })
        #expect(theme.words.allSatisfy { $0.allSatisfy { $0.isUppercase && $0.isLetter } })
        #expect(Set(theme.words).count == theme.words.count, "a duplicate in the pool can be drawn twice")
    }

    // MARK: - Finding a word

    @Test func aSelectionIsMatchedByItsCellsNotItsLetters() {
        let puzzle = WordSearchGenerator.puzzle(seed: 3, theme: .travel)
        let placement = puzzle.placements[0]
        let cells = placement.cells(size: WordSearchPuzzle.size)

        #expect(puzzle.placement(coveringCells: cells) == placement)
        // Dragged the other way. The same word, and the player should not have to guess which end
        // to start from.
        #expect(puzzle.placement(coveringCells: cells.reversed()) == placement)
        // A run of cells that is not a placement finds nothing, even if the letters happen to work.
        #expect(puzzle.placement(coveringCells: [0]) == nil)
    }

    /// Crossings are the point of a word search, and the grid now draws a loop per word partly so
    /// that a shared letter reads as belonging to both. If the generator stopped producing them —
    /// a stricter `place`, a different search order — the loops would still be correct and the
    /// puzzles would quietly become a set of parallel lines nobody has to think about.
    @Test("generated grids actually cross their words")
    func gridsContainCrossings() {
        var seedsWithCrossings = 0
        let seeds = (1...20).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }

        for seed in seeds {
            let puzzle = WordSearchGenerator.puzzle(for: seed, theme: .travel)
            var seen: [Int: Int] = [:]
            var crossings = 0
            for placement in puzzle.placements {
                for cell in placement.cells(size: WordSearchPuzzle.size) {
                    seen[cell, default: 0] += 1
                    if seen[cell] == 2 { crossings += 1 }
                }
            }
            if crossings > 0 { seedsWithCrossings += 1 }
        }

        // Every grid, which is what scoring placements by shared letters buys: before that the
        // generator took the first fit and only nine of these twenty seeds crossed anywhere.
        //
        // Seeded, so this is a fact about these twenty grids rather than a probability. If a word
        // list or the placement order changes and some seed can genuinely only fit in free space,
        // this is allowed to be relaxed — but it should be relaxed deliberately, not by deleting
        // it, because a grid of parallel runs still passes every other test in this file.
        #expect(
            seedsWithCrossings >= seeds.count,
            "only \(seedsWithCrossings) of \(seeds.count) grids had any word crossing another"
        )
    }
}
