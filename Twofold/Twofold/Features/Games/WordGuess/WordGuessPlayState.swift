//
//  WordGuessPlayState.swift
//  Twofold
//
//  A Word Guess board in progress, in a form that survives the app being killed.
//
//  Rides in `game_responses.answer` as one string, through the same `GameAnswerPayload` every
//  other game uses — the same arrangement `SudokuPlayState` documents at length. A board really is
//  one value: the words guessed so far, in order, and how long it took.
//
//  What is *not* stored is the answer. It is derived from the round's `content_id` on each device
//  (see `WordGuessWords.answer(for:)`), and writing it into a row both partners can read would
//  hand either of them the solution.
//
//  Nor are the colours stored. They are a function of the guesses and the answer, so keeping them
//  would be keeping a second copy of a derived fact — and the copy that can disagree with the
//  board is the one that eventually does.
//

import Foundation

struct WordGuessPlayState: Equatable {
    /// Committed guesses, in the order they were made. Always real words of the right length: the
    /// board refuses anything else before it gets here.
    private(set) var guesses: [String]
    /// Seconds spent at the board. Same rule as sudoku's clock — it runs only while the screen is
    /// up, so a board left open overnight has not been played overnight.
    var elapsed: TimeInterval
    /// The word this board is being played against. Held rather than passed in everywhere, so
    /// `isSolved` and `marks` cannot be asked about a different word by accident.
    let answer: String

    init(answer: String, guesses: [String] = [], elapsed: TimeInterval = 0) {
        self.answer = answer.lowercased()
        self.guesses = guesses.map { $0.lowercased() }
        self.elapsed = elapsed
    }

    // MARK: - State

    var isSolved: Bool { guesses.last == answer }
    /// Out of guesses without getting it. A finished board, but not a won one.
    var isFailed: Bool { !isSolved && guesses.count >= WordGuessWords.maxGuesses }
    var isComplete: Bool { isSolved || isFailed }
    /// 1...6 when solved, nil when not — the number people actually report to each other.
    var guessesUsed: Int? { isSolved ? guesses.count : nil }
    var canGuessAgain: Bool { !isComplete }

    /// The colours for one committed row.
    func marks(forGuessAt index: Int) -> [WordGuessMark] {
        guard guesses.indices.contains(index) else { return [] }
        return WordGuessEvaluation.marks(guess: guesses[index], answer: answer)
    }

    /// What every key on the keyboard knows so far.
    var keyboardMarks: [Character: WordGuessMark] {
        WordGuessEvaluation.keyboardMarks(guesses: guesses, answer: answer)
    }

    // MARK: - Playing

    /// Why a guess was turned away, so the board can say which mistake was made. "Not a word" and
    /// "not enough letters" are different problems and the second one is the player's own typing.
    enum Rejection: Equatable {
        case wrongLength
        case notAWord
        case alreadyGuessed
        case boardFinished
    }

    /// Commits a guess, or explains why not.
    ///
    /// `alreadyGuessed` is a rejection rather than an allowed waste of a turn. Retyping a word you
    /// have already had back is never a strategy — it is a mis-tap or a forgotten row — and
    /// spending one of six guesses on it would be a punishment for the board being hard to read.
    @discardableResult
    mutating func commit(_ word: String) -> Rejection? {
        guard !isComplete else { return .boardFinished }
        let candidate = word.lowercased()
        guard candidate.count == WordGuessWords.length else { return .wrongLength }
        guard !guesses.contains(candidate) else { return .alreadyGuessed }
        guard WordGuessWords.isAllowed(candidate) else { return .notAWord }
        guesses.append(candidate)
        return nil
    }
}

// MARK: - Persistence

extension WordGuessPlayState {
    /// `wordguess.v1|<comma-separated guesses>|<elapsed seconds>|<0 or 1 solved>`
    ///
    /// The answer is deliberately absent, so this payload cannot leak it to the partner who can
    /// read the row. That means decoding needs the answer supplied from the puzzle id — the same
    /// arrangement as `SudokuPlayState.decoded` taking the puzzle.
    ///
    /// `solved` is stored even though it is derivable, for the same reason `summary` exists: the
    /// stats and comparison paths hold the string without the word it was played against, and
    /// recomputing it there would mean re-deriving a puzzle to read one boolean.
    private static let version1 = "wordguess.v1"

    var encoded: String {
        [
            Self.version1,
            guesses.joined(separator: ","),
            String(Int(elapsed.rounded())),
            isSolved ? "1" : "0"
        ].joined(separator: "|")
    }

    /// How it went, for a caller holding the string but not the word.
    ///
    /// `guessCount` is what both the comparison and the stats compare on, and it is meaningful
    /// whether or not the board was solved — six guesses and a miss is a different result from six
    /// guesses and a win, which is why `solved` travels alongside rather than being inferred from
    /// the count.
    static func summary(from string: String) -> WordGuessSummary? {
        let fields = string.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 4, fields[0] == Substring(version1) else { return nil }
        guard let seconds = Int(fields[2]), seconds >= 0 else { return nil }
        guard fields[3] == "0" || fields[3] == "1" else { return nil }

        // An empty guesses field splits to [""], not to [] — a board with no guesses on it yet.
        let guesses = fields[1].isEmpty ? [] : fields[1].split(separator: ",").map(String.init)
        guard guesses.allSatisfy({ $0.count == WordGuessWords.length }) else { return nil }
        guard guesses.count <= WordGuessWords.maxGuesses else { return nil }

        return WordGuessSummary(
            guessCount: guesses.count,
            solved: fields[3] == "1",
            elapsed: TimeInterval(seconds)
        )
    }

    /// Reads a board back, or gives up.
    ///
    /// Refuses rather than repairs, exactly as sudoku does: a board restored wrong is worse than a
    /// board restored not at all, because the player cannot tell which they are looking at.
    static func decoded(from string: String, answer: String) -> WordGuessPlayState? {
        let fields = string.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 4, fields[0] == Substring(version1) else { return nil }
        guard let seconds = Int(fields[2]), seconds >= 0 else { return nil }

        let guesses = fields[1].isEmpty ? [] : fields[1].split(separator: ",").map(String.init)
        guard guesses.allSatisfy({ $0.count == WordGuessWords.length }) else { return nil }
        guard guesses.count <= WordGuessWords.maxGuesses else { return nil }
        // Written by a build whose answer list differed, or by a different puzzle entirely. Both
        // produce a board whose colours would be nonsense against this word.
        guard Set(guesses).count == guesses.count else { return nil }

        return WordGuessPlayState(answer: answer, guesses: guesses, elapsed: TimeInterval(seconds))
    }
}

/// One finished (or abandoned) board, as the comparison and the stats see it.
struct WordGuessSummary: Equatable, Hashable {
    let guessCount: Int
    let solved: Bool
    let elapsed: TimeInterval

    /// First guess, straight in. Worth naming because it is the only result that is luck rather
    /// than play, and the comparison should not call it a victory over anybody.
    var isHoleInOne: Bool { solved && guessCount == 1 }
}
