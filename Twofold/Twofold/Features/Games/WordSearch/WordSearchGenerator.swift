//
//  WordSearchGenerator.swift
//  Twofold
//
//  Builds a grid from a puzzle's identity, the same way `SudokuGenerator` does.
//
//  Same seed in, same grid out, on both partners' phones and every future version — see
//  `PuzzleRandom`, which carries most of that weight. Nothing about the grid is ever stored or
//  sent: both devices read the round's `content_id` and arrive at the same letters.
//

import Foundation

/// One of the eight ways a word can run. Stored as a row/column step.
///
/// All eight, including backwards and upwards. A search restricted to left-to-right and downwards
/// is findable by reading the grid rather than searching it, which is a different and much duller
/// puzzle.
enum WordSearchDirection: Int, CaseIterable, Codable, Hashable {
    case east, west, south, north
    case southEast, southWest, northEast, northWest

    var step: (row: Int, column: Int) {
        switch self {
        case .east: (0, 1)
        case .west: (0, -1)
        case .south: (1, 0)
        case .north: (-1, 0)
        case .southEast: (1, 1)
        case .southWest: (1, -1)
        case .northEast: (-1, 1)
        case .northWest: (-1, -1)
        }
    }
}

/// Where one word ended up. The cells are derived rather than stored, so a placement cannot
/// disagree with itself.
struct WordSearchPlacement: Equatable, Hashable {
    let word: String
    /// Index of the word's first letter, row-major.
    let start: Int
    let direction: WordSearchDirection

    func cells(size: Int) -> [Int] {
        let step = direction.step
        var row = start / size
        var column = start % size
        var result: [Int] = []
        for _ in 0..<word.count {
            result.append(row * size + column)
            row += step.row
            column += step.column
        }
        return result
    }
}

struct WordSearchPuzzle: Equatable {
    static let size = 10
    /// How many words a grid hides. Enough to take a few minutes, few enough that a ten-by-ten can
    /// hold them all without the filler letters disappearing.
    static let wordCount = 8

    let letters: [Character]
    let placements: [WordSearchPlacement]
    let theme: WordSearchTheme

    var words: [String] { placements.map(\.word) }

    subscript(index: Int) -> Character { letters[index] }

    /// The straight run of cells from one to another, or nil if they do not line up.
    ///
    /// A word search only accepts straight lines, and this is where that rule lives. The player
    /// drags from a first letter to a last one; anything that is not a row, a column or a true
    /// diagonal is not a selection at all, which is why this returns nil rather than a best guess —
    /// a dragged finger passes over a great many cells that were never meant.
    static func line(from start: Int, to end: Int, size: Int) -> [Int]? {
        guard (0..<(size * size)).contains(start), (0..<(size * size)).contains(end) else { return nil }
        let startRow = start / size, startColumn = start % size
        let endRow = end / size, endColumn = end % size
        let rowDelta = endRow - startRow, columnDelta = endColumn - startColumn

        // A single cell is a legal line of one — it is what a tap is, before the finger moves.
        if rowDelta == 0 && columnDelta == 0 { return [start] }
        // Straight means one of the three: same row, same column, or an exact diagonal. Anything
        // else — two across and one down — is a drag that has wandered.
        guard rowDelta == 0 || columnDelta == 0 || abs(rowDelta) == abs(columnDelta) else { return nil }

        let steps = max(abs(rowDelta), abs(columnDelta))
        let rowStep = rowDelta == 0 ? 0 : rowDelta / abs(rowDelta)
        let columnStep = columnDelta == 0 ? 0 : columnDelta / abs(columnDelta)
        return (0...steps).map { step in
            (startRow + rowStep * step) * size + (startColumn + columnStep * step)
        }
    }

    /// The placement occupying exactly these cells, in either direction.
    ///
    /// Matched on cells rather than on the letters they spell. A grid of a hundred letters will
    /// sometimes spell a hidden word somewhere it was never placed, and accepting that would light
    /// up a run of letters that is not the word the list is pointing at — the player would see the
    /// word tick off and the highlight land somewhere that looks wrong.
    func placement(coveringCells cells: [Int]) -> WordSearchPlacement? {
        placements.first { placement in
            let placed = placement.cells(size: Self.size)
            return placed == cells || placed == cells.reversed()
        }
    }
}

enum WordSearchGenerator {

    /// The grid for this identity. Same id and theme, same grid — always.
    static func puzzle(for id: UUID, theme: WordSearchTheme) -> WordSearchPuzzle {
        var random = PuzzleRandom(puzzleID: id)
        return generate(using: &random, theme: theme)
    }

    /// Seed-based entry point, for tests and anywhere an identity is not a UUID.
    static func puzzle(seed: UInt64, theme: WordSearchTheme) -> WordSearchPuzzle {
        var random = PuzzleRandom(seed: seed)
        return generate(using: &random, theme: theme)
    }

    // MARK: -

    private static func generate(using random: inout PuzzleRandom, theme: WordSearchTheme) -> WordSearchPuzzle {
        let size = WordSearchPuzzle.size
        var letters = [Character](repeating: " ", count: size * size)
        var placements: [WordSearchPlacement] = []

        // Longest first. A long word has the fewest places it can go, so placing it while the grid
        // is empty is the difference between a grid that packs and one that gives up two words
        // short. Ties broken by the shuffled order, so the choice among equal-length words is still
        // the seed's.
        let candidates = random.shuffled(theme.words)
            .sorted { $0.count > $1.count }

        for word in candidates where placements.count < WordSearchPuzzle.wordCount {
            let letterArray = Array(word)
            guard letterArray.count <= size else { continue }

            // Every legal starting cell and direction, in a seeded order, and take the first that
            // fits. Trying random placements a fixed number of times instead would make the grid
            // depend on how many attempts happened to fail, which is the kind of thing that changes
            // when the word lists do.
            var options: [(start: Int, direction: WordSearchDirection)] = []
            for start in 0..<(size * size) {
                for direction in WordSearchDirection.allCases {
                    options.append((start, direction))
                }
            }
            options = random.shuffled(options)

            // Of the placements that fit, prefer the one sharing the most letters with what is
            // already on the grid.
            //
            // Taking the first fit put nearly every word in empty space — on a mostly-empty grid
            // the first shuffled option almost always is empty — and only nine grids in twenty
            // had a single crossing anywhere. A grid of parallel runs is a worse puzzle: crossings
            // are what make a letter ambiguous, and ambiguity is the whole search.
            //
            // Scored rather than required. A word whose only fits are in free space still gets
            // placed, because the best score among fitting options may legitimately be zero, and
            // refusing it would cost the grid a word to gain a crossing.
            var best: (start: Int, direction: WordSearchDirection, grid: [Character], shared: Int)?
            for option in options {
                guard let placed = place(letterArray, at: option.start, direction: option.direction, in: letters, size: size) else { continue }
                let shared = sharedLetterCount(letterArray, at: option.start, direction: option.direction, in: letters, size: size)
                if best == nil || shared > best!.shared {
                    best = (option.start, option.direction, placed, shared)
                    // Nothing can beat every letter shared, and the options are already in seeded
                    // order, so there is no reason to keep scoring.
                    if shared == letterArray.count { break }
                }
            }

            if let best {
                placements.append(WordSearchPlacement(word: word, start: best.start, direction: best.direction))
                letters = best.grid
            }
        }

        // Everything still empty becomes a letter. Drawn from the placed words' own letters rather
        // than from the alphabet: uniform random filler is visibly different from English text —
        // it is full of Q, X and Z — and the hidden words stand out as the only ordinary-looking
        // runs on the grid.
        let pool = Array(placements.map(\.word).joined())
        for index in letters.indices where letters[index] == " " {
            letters[index] = pool.isEmpty
                ? Character(UnicodeScalar(65 + random.next(upperBound: 26))!)
                : pool[random.next(upperBound: pool.count)]
        }

        return WordSearchPuzzle(letters: letters, placements: placements, theme: theme)
    }

    /// How many of this word's letters would land on a letter already written, rather than on empty
    /// space. Only meaningful for a placement `place` has already accepted — it assumes agreement,
    /// and counts occupied cells rather than re-checking them.
    private static func sharedLetterCount(
        _ word: [Character],
        at start: Int,
        direction: WordSearchDirection,
        in letters: [Character],
        size: Int
    ) -> Int {
        let step = direction.step
        var row = start / size
        var column = start % size
        var shared = 0

        for _ in word {
            guard row >= 0, row < size, column >= 0, column < size else { return shared }
            if letters[row * size + column] != " " { shared += 1 }
            row += step.row
            column += step.column
        }
        return shared
    }

    /// Writes a word in, if it fits and agrees with everything already there.
    ///
    /// Returns the grid it would produce rather than mutating, so a placement that turns out not to
    /// fit leaves nothing half-written behind. Crossing an existing word is allowed and wanted — a
    /// grid where no two words touch is a grid where finding one tells you nothing.
    private static func place(
        _ word: [Character],
        at start: Int,
        direction: WordSearchDirection,
        in letters: [Character],
        size: Int
    ) -> [Character]? {
        let step = direction.step
        var row = start / size
        var column = start % size
        var candidate = letters

        for letter in word {
            guard row >= 0, row < size, column >= 0, column < size else { return nil }
            let index = row * size + column
            guard candidate[index] == " " || candidate[index] == letter else { return nil }
            candidate[index] = letter
            row += step.row
            column += step.column
        }
        return candidate
    }
}
