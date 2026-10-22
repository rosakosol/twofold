//
//  GameResultShareData.swift
//  Twofold
//
//  Plain snapshot of everything a share card needs — built once by `GameResultsView` from its
//  own already-computed state, so the card views themselves stay pure and don't reach back into
//  a live `GameSessionStore`. Same reasoning as `RelationshipStatsShareCard` taking plain
//  `Couple`/`Trip`/`Memory` values rather than a store.
//

import Foundation

/// One topic + both answers from a multi-round Deep Conversations deck — each becomes its own card
/// in the share sheet, swiped between. Deep Conversations answers are free text with no
/// right answer to compare against (unlike This-or-That/More-Likely's `matchPercent`), so this is
/// deliberately about picking *which* exchange to show off, never whether the two of you "matched."
struct GameResultShareRound: Identifiable {
    let id = UUID()
    let question: String
    let myAnswer: String
    let partnerAnswer: String
}

struct GameResultShareData {
    let gameType: GameType
    let title: String
    let isDaily: Bool
    let me: Person
    let partner: Person

    // MARK: Scores

    /// 0...100 — thisOrThat / moreLikely only.
    let matchPercent: Int?
    let triviaMyScore: Int?
    let triviaPartnerScore: Int?
    let triviaTotalRounds: Int?
    /// Every topic from a multi-round Deep Conversations deck (not the Daily Question, which has
    /// exactly one round already covered by `singleRoundQuestion` below, so this stays nil for
    /// it). nil for every other game type.
    let deepConversationRounds: [GameResultShareRound]?

    // MARK: Single round

    /// The Daily Question's one question and both answers. nil for a multi-round deck, whose
    /// rounds are in `deepConversationRounds`.
    var singleRoundQuestion: String?
    var myAnswer: String?
    var partnerAnswer: String?
    let dailyStreak: Int?

    // MARK: Sudoku

    /// Both finished solve times, in seconds — sudoku only, nil everywhere else. The difficulty
    /// rides in `title` rather than a field of its own, since that is all the card does with it.
    ///
    /// Two plain times rather than a `SudokuComparison`: that type carries the partner's name, and
    /// this struct already has `partner`. Storing it twice is how the two end up disagreeing.
    /// The card rebuilds the comparison from these and `partner.name` where it needs the wording.
    /// Defaulted so every existing call site keeps compiling without naming a sudoku field.
    var sudokuMyElapsed: TimeInterval? = nil
    var sudokuPartnerElapsed: TimeInterval? = nil
    /// What each of them used getting there.
    ///
    /// On the card for the same reason it is on the comparison: two times side by side with one
    /// called faster is only a race if both solves cost the same. A card that leaves this off is
    /// the version of that claim most likely to be seen by other people, and the one its subject
    /// has least chance to correct.
    var sudokuMyAids: SudokuSolveSummary? = nil
    var sudokuPartnerAids: SudokuSolveSummary? = nil

    // MARK: Word Guess

    /// Both finished boards and the day's date — Word Guess only. The card shows the colours of
    /// each guess and never the letters, so it can go to someone who hasn't played the word yet.
    var wordGuessMine: WordGuessPlayState? = nil
    var wordGuessTheirs: WordGuessPlayState? = nil
    var playedAt: Date? = nil

    // MARK: Connect 4

    /// The board, row 0 at the top. Shared while a game is still going, too.
    var connectFourCells: [ConnectFourBoard.Disc?]? = nil
    /// "Ewin's move", "Rosa wins", "A draw".
    var connectFourStatus: String? = nil
    /// Who played first, which decides whose pieces are whose.
    var connectFourFirstIsMe = false
    /// The four in a row, when the game was won.
    var connectFourWinning: [Int] = []

    static func wordGuess(
        mine: WordGuessPlayState,
        theirs: WordGuessPlayState,
        me: Person,
        partner: Person,
        date: Date
    ) -> GameResultShareData {
        GameResultShareData(
            gameType: .wordGuess,
            title: GameType.wordGuess.displayName,
            isDaily: true,
            me: me,
            partner: partner,
            matchPercent: nil,
            triviaMyScore: nil,
            triviaPartnerScore: nil,
            triviaTotalRounds: nil,
            deepConversationRounds: nil,
            dailyStreak: nil,
            wordGuessMine: mine,
            wordGuessTheirs: theirs,
            playedAt: date
        )
    }

    static func connectFour(
        board: ConnectFourBoard,
        status: String,
        firstIsMe: Bool,
        me: Person,
        partner: Person
    ) -> GameResultShareData {
        GameResultShareData(
            gameType: .connectFour,
            title: GameType.connectFour.displayName,
            isDaily: false,
            me: me,
            partner: partner,
            matchPercent: nil,
            triviaMyScore: nil,
            triviaPartnerScore: nil,
            triviaTotalRounds: nil,
            deepConversationRounds: nil,
            dailyStreak: nil,
            connectFourCells: board.cells,
            connectFourStatus: status,
            connectFourFirstIsMe: firstIsMe,
            connectFourWinning: board.winningLine()?.cells ?? []
        )
    }
}
