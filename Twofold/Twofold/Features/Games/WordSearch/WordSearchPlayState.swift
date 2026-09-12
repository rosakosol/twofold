//
//  WordSearchPlayState.swift
//  Twofold
//
//  A grid in progress: which words have been found, and how long it has taken.
//
//  Rides in `game_responses.answer` as one string, through the same `GameAnswerPayload` every other
//  game uses — the arrangement `SudokuPlayState` documents at length, and for the same reason: one
//  response row per player, written when the grid is finished, so a row in that table keeps
//  meaning "this player is done".
//
//  What is stored is the list of words found. Not the cells, which are derivable from the puzzle
//  and the word, and not the grid, which is derivable from the round's id. A payload that carried
//  either would be a second copy of a fact — and the copy that can disagree with the board is the
//  one that eventually does.
//

import Foundation

struct WordSearchPlayState: Equatable {
    /// Words found, in the order they were found. Ordered rather than a set so a future "you found
    /// them in this order" has the data, and because an order makes the payload stable to compare.
    private(set) var found: [String]
    /// Seconds spent at the grid. Runs only while the screen is up, like every other puzzle here.
    var elapsed: TimeInterval
    let puzzle: WordSearchPuzzle

    init(puzzle: WordSearchPuzzle, found: [String] = [], elapsed: TimeInterval = 0) {
        self.puzzle = puzzle
        // Filtered against the puzzle rather than trusted. A restored payload naming a word this
        // grid does not contain would otherwise count towards completion and finish a grid that
        // still has words on it.
        self.found = found.filter { puzzle.words.contains($0) }
        self.elapsed = elapsed
    }

    // MARK: - State

    var isComplete: Bool { found.count == puzzle.placements.count }
    var remainingCount: Int { puzzle.placements.count - found.count }
    var totalCount: Int { puzzle.placements.count }

    func isFound(_ word: String) -> Bool { found.contains(word) }

    /// The placements of the words found, in the order they were found.
    ///
    /// The grid draws a loop around each one rather than shading their cells, so it needs the runs
    /// themselves — where each word starts, which way it goes — and not the flat set of cells
    /// `foundCells` gives. Ordered so a word keeps the same loop colour for the whole game: the
    /// colours are what tell two crossing words apart, and a set would reshuffle them on every
    /// find.
    var foundPlacements: [WordSearchPlacement] {
        found.compactMap { word in puzzle.placements.first { $0.word == word } }
    }

    /// Every cell belonging to a word already found.
    var foundCells: Set<Int> {
        var cells: Set<Int> = []
        for placement in puzzle.placements where found.contains(placement.word) {
            cells.formUnion(placement.cells(size: WordSearchPuzzle.size))
        }
        return cells
    }

    // MARK: - Playing

    /// Takes a straight run of cells and, if it is a word that has not been found yet, records it.
    ///
    /// Returns the placement so the caller can celebrate the specific word; nil covers both "that
    /// is not one of them" and "you already have that one", which are the same non-event from the
    /// grid's point of view — nothing changes, and nothing should be announced.
    @discardableResult
    mutating func find(cells: [Int]) -> WordSearchPlacement? {
        guard let placement = puzzle.placement(coveringCells: cells) else { return nil }
        guard !found.contains(placement.word) else { return nil }
        found.append(placement.word)
        return placement
    }
}

// MARK: - Persistence

extension WordSearchPlayState {
    /// `wordsearch.v1|<comma-separated found words>|<elapsed seconds>|<0 or 1 complete>`
    ///
    /// `complete` is stored even though it is derivable, for the same reason `summary` exists: the
    /// comparison holds this string without the grid it was played on, and deriving a whole puzzle
    /// there to read one boolean would be the expensive way to learn something already known.
    private static let version1 = "wordsearch.v1"

    var encoded: String {
        [
            Self.version1,
            found.joined(separator: ","),
            String(Int(elapsed.rounded())),
            isComplete ? "1" : "0"
        ].joined(separator: "|")
    }

    /// How it went, for a caller holding the string but not the grid.
    static func summary(from string: String) -> WordSearchSummary? {
        let fields = string.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 4, fields[0] == Substring(version1) else { return nil }
        guard let seconds = Int(fields[2]), seconds >= 0 else { return nil }
        guard fields[3] == "0" || fields[3] == "1" else { return nil }

        // An empty found field splits to [""], not to [] — a grid with nothing found yet.
        let found = fields[1].isEmpty ? [] : fields[1].split(separator: ",").map(String.init)
        guard Set(found).count == found.count else { return nil }

        return WordSearchSummary(
            foundCount: found.count,
            complete: fields[3] == "1",
            elapsed: TimeInterval(seconds)
        )
    }

    /// Reads a grid's progress back, or gives up.
    ///
    /// Refuses rather than repairs, as every other puzzle here does: a board restored wrong is
    /// worse than one restored not at all, because the player cannot tell which they have.
    static func decoded(from string: String, puzzle: WordSearchPuzzle) -> WordSearchPlayState? {
        let fields = string.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 4, fields[0] == Substring(version1) else { return nil }
        guard let seconds = Int(fields[2]), seconds >= 0 else { return nil }

        let found = fields[1].isEmpty ? [] : fields[1].split(separator: ",").map(String.init)
        guard Set(found).count == found.count else { return nil }
        // Written against a different grid, or by a build whose word lists differed. Either way the
        // words named are not the words on this board.
        guard found.allSatisfy({ puzzle.words.contains($0) }) else { return nil }

        return WordSearchPlayState(puzzle: puzzle, found: found, elapsed: TimeInterval(seconds))
    }
}

/// One finished grid, as the comparison sees it.
struct WordSearchSummary: Equatable, Hashable {
    let foundCount: Int
    let complete: Bool
    let elapsed: TimeInterval
}
