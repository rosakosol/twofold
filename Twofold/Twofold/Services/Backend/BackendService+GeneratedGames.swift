//
//  BackendService+GeneratedGames.swift
//  Twofold
//
//  The generated puzzles: Sudoku, Word Guess, Word Search and Connect 4.
//

import Foundation
import Supabase

extension BackendService {

    /// Starts, or picks back up, a sudoku at this difficulty.
    ///
    /// `puzzleID` is the whole of the puzzle. There is no content row behind it and nothing to
    /// fetch: both partners run this uuid through `SudokuGenerator` and arrive at the same grid,
    /// which is what lets a puzzle be played with no connection at all once it has been started.
    ///
    /// `resumed` distinguishes "here is your half-finished Hard" from "here is a new one" — the
    /// server decides that, since only it can see whether the couple already has one open.
    struct SudokuSessionStart: Decodable {
        let sessionID: UUID
        let puzzleID: UUID
        let difficulty: SudokuDifficulty
        let resumed: Bool

        enum CodingKeys: String, CodingKey {
            case difficulty, resumed
            case sessionID = "session_id"
            case puzzleID = "puzzle_id"
        }
    }

    static func startSudokuSession(difficulty: SudokuDifficulty) async throws -> SudokuSessionStart {
        nonisolated struct Params: Encodable {
            var pDifficulty: String
            enum CodingKeys: String, CodingKey { case pDifficulty = "p_difficulty" }
        }
        let start: SudokuSessionStart = try await rpcSingle("start_sudoku_session", params: Params(pDifficulty: difficulty.rawValue))
        Analytics.capture(Analytics.Event.sessionStart, properties: [
            "game_type": GameType.sudoku.rawValue,
            "difficulty": difficulty.rawValue,
            "resumed": start.resumed
        ])
        return start
    }

    /// Starts, or picks back up, the couple's Word Guess board.
    ///
    /// `puzzleID` is the whole of the puzzle, as it is for sudoku: both partners run this uuid
    /// through `WordGuessWords.answer(for:)` and land on the same word, which the server never
    /// learns and never stores — it is readable by both partners wherever it is put.
    ///
    /// Throws `BackendError.wordGuessDailyLimit` when a Plus couple has already had today's word.
    /// That is an ordinary outcome rather than a failure, and the picker says so.
    struct WordGuessSessionStart: Decodable {
        let sessionID: UUID
        let puzzleID: UUID
        let resumed: Bool

        enum CodingKeys: String, CodingKey {
            case resumed
            case sessionID = "session_id"
            case puzzleID = "puzzle_id"
        }
    }

    /// One past Sudoku, as the difficulty screen lists it.
    struct SudokuHistoryEntry: Identifiable, Hashable {
        let id: UUID
        let playedAt: Date
        let difficulty: SudokuDifficulty?
        /// This person's solving time, once they've completed the grid.
        let mine: TimeInterval?
        /// Theirs, once both have finished: RLS keeps a partner's response back until then.
        let partner: TimeInterval?
        let isAbandoned: Bool
    }

    /// The couple's recent puzzles, newest first, in one request: each session with its round (for
    /// the difficulty) and whichever responses the caller is allowed to see.
    static func fetchSudokuHistory(limit: Int = 30) async throws -> [SudokuHistoryEntry] {
        struct Row: Decodable {
            struct Round: Decodable { let difficulty: SudokuDifficulty? }
            struct Response: Decodable {
                let responderId: UUID
                let answer: GameAnswerPayload
                enum CodingKeys: String, CodingKey { case answer, responderId = "responder_id" }
            }
            let id: UUID
            let status: GameSessionStatus
            let createdAt: Date
            let rounds: [Round]
            let responses: [Response]
            enum CodingKeys: String, CodingKey {
                case id, status
                case createdAt = "created_at"
                case rounds = "game_session_rounds"
                case responses = "game_responses"
            }
        }

        let rows: [Row] = try await supabase
            .from("game_sessions")
            .select("id, status, created_at, game_session_rounds(difficulty), game_responses(responder_id, answer)")
            .eq("game_type", value: GameType.sudoku.rawValue)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let me = currentUserID
        // A time only for a grid that was completed: a saved board in progress has an elapsed time
        // too, and it is not a result.
        func time(_ response: Row.Response?) -> TimeInterval? {
            guard let response, let summary = SudokuPlayState.summary(from: response.answer.value),
                  summary.isComplete else { return nil }
            return summary.elapsed
        }
        return rows.map { row in
            SudokuHistoryEntry(
                id: row.id,
                playedAt: row.createdAt,
                difficulty: row.rounds.first?.difficulty,
                mine: time(row.responses.first { $0.responderId == me }),
                partner: time(row.responses.first { $0.responderId != me }),
                isAbandoned: row.status == .abandoned
            )
        }
    }

    /// One past Word Guess game, as the entry screen lists it.
    struct WordGuessHistoryEntry: Identifiable, Hashable {
        let id: UUID
        /// The round's content id, which is the puzzle: `WordGuessWords.answer(for:)` turns it into
        /// the word. The word itself is never stored.
        let puzzleID: UUID
        let playedAt: Date
        let status: GameSessionStatus
        /// Nil until this person has finished the board.
        let mine: WordGuessSummary?
        /// Nil until both have finished: RLS hides a partner's response before then, which is what
        /// keeps their score from spoiling a board still in play.
        let partner: WordGuessSummary?
    }

    /// The couple's recent Word Guess games, newest first, in one request: each session with its
    /// round and whichever responses the caller is allowed to see.
    static func fetchWordGuessHistory(limit: Int = 30) async throws -> [WordGuessHistoryEntry] {
        struct Row: Decodable {
            struct Round: Decodable {
                let contentId: UUID
                enum CodingKeys: String, CodingKey { case contentId = "content_id" }
            }
            struct Response: Decodable {
                let responderId: UUID
                let answer: GameAnswerPayload
                enum CodingKeys: String, CodingKey { case answer, responderId = "responder_id" }
            }
            let id: UUID
            let status: GameSessionStatus
            let createdAt: Date
            let rounds: [Round]
            let responses: [Response]
            enum CodingKeys: String, CodingKey {
                case id, status
                case createdAt = "created_at"
                case rounds = "game_session_rounds"
                case responses = "game_responses"
            }
        }

        let rows: [Row] = try await supabase
            .from("game_sessions")
            .select("id, status, created_at, game_session_rounds(content_id), game_responses(responder_id, answer)")
            .eq("game_type", value: GameType.wordGuess.rawValue)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let me = currentUserID
        return rows.compactMap { row in
            guard let puzzleID = row.rounds.first?.contentId else { return nil }
            let mine = row.responses.first { $0.responderId == me }
            let theirs = row.responses.first { $0.responderId != me }
            return WordGuessHistoryEntry(
                id: row.id,
                puzzleID: puzzleID,
                playedAt: row.createdAt,
                status: row.status,
                mine: mine.flatMap { WordGuessPlayState.summary(from: $0.answer.value) },
                partner: theirs.flatMap { WordGuessPlayState.summary(from: $0.answer.value) }
            )
        }
    }

    static func startWordGuessSession() async throws -> WordGuessSessionStart {
        // A Plus couple that has had today's word gets `word_guess_daily_limit`, which
        // `BackendFailure` names `.wordGuessDailyLimit`.
        let start: WordGuessSessionStart = try await rpcSingle("start_word_guess_session")
        Analytics.capture(Analytics.Event.sessionStart, properties: [
            "game_type": GameType.wordGuess.rawValue,
            "resumed": start.resumed
        ])
        return start
    }

    /// Starts, or picks back up, a Word Search at this theme.
    ///
    /// `puzzleID` is the whole of the grid, as it is for the other generated games: both partners
    /// run this uuid and the theme through `WordSearchGenerator` and arrive at the same hundred
    /// letters, which is what lets a started grid be played with no connection at all.
    struct WordSearchSessionStart: Decodable {
        let sessionID: UUID
        let puzzleID: UUID
        let theme: WordSearchTheme
        let resumed: Bool

        enum CodingKeys: String, CodingKey {
            case theme, resumed
            case sessionID = "session_id"
            case puzzleID = "puzzle_id"
        }
    }

    static func startWordSearchSession(theme: WordSearchTheme) async throws -> WordSearchSessionStart {
        nonisolated struct Params: Encodable {
            var pTheme: String
            enum CodingKeys: String, CodingKey { case pTheme = "p_theme" }
        }
        // `word_search_requires_premium` comes back as `.wordSearchRequiresPremium` rather than
        // shown raw: the screen has a real thing to offer instead. See 20261111000700.
        let start: WordSearchSessionStart = try await rpcSingle("start_word_search_session", params: Params(pTheme: theme.rawValue))
        Analytics.capture(Analytics.Event.sessionStart, properties: [
            "game_type": GameType.wordSearch.rawValue,
            "theme": theme.rawValue,
            "resumed": start.resumed
        ])
        return start
    }

    // MARK: - Connect 4

    /// One row of `game_moves`. The board is this list replayed in order — see `ConnectFourBoard`.
    struct GameMove: Identifiable, Hashable, Decodable {
        let id: UUID
        var sessionID: UUID
        var moveNumber: Int
        var playerID: UUID
        var move: String
        var createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, move
            case sessionID = "session_id"
            case moveNumber = "move_number"
            case playerID = "player_id"
            case createdAt = "created_at"
        }
    }

    struct ConnectFourStart: Decodable {
        let sessionID: UUID
        let resumed: Bool

        enum CodingKeys: String, CodingKey {
            case resumed
            case sessionID = "session_id"
        }
    }

    /// What a move did. The server works this out rather than being told — see
    /// 20261013000200_play_connect_four.sql for why ending the game is its decision and not the
    /// client's.
    struct ConnectFourMoveResult: Decodable {
        let moveNumber: Int
        let finished: Bool
        let winnerID: UUID?
        let isDraw: Bool

        enum CodingKeys: String, CodingKey {
            case finished
            case moveNumber = "move_number"
            case winnerID = "winner_id"
            case isDraw = "is_draw"
        }
    }

    static func startConnectFourSession() async throws -> ConnectFourStart {
        // Refused as `.connectFourRequiresPremium` or `.connectFourNeedsPartner`.
        let start: ConnectFourStart = try await rpcSingle("start_connect_four_session")
        Analytics.capture(Analytics.Event.sessionStart, properties: [
            "game_type": GameType.connectFour.rawValue,
            "resumed": start.resumed
        ])
        return start
    }

    /// Drops a disc, and reports whether that ended the game.
    ///
    /// The turn rule lives in the RPC and in a unique index on `(session_id, move_number)`. Both
    /// matter: the check produces a useful error, and the index is what makes the outcome correct
    /// when two moves race — see the migration's header.
    static func playConnectFourMove(sessionID: UUID, column: Int) async throws -> ConnectFourMoveResult {
        nonisolated struct Params: Encodable {
            var pSessionId: UUID
            var pColumn: Int
            enum CodingKeys: String, CodingKey {
                case pSessionId = "p_session_id"
                case pColumn = "p_column"
            }
        }
        // Three ordinary outcomes rather than failures — the board raced, or was finished, or the
        // column filled up — come back named: `.notYourTurn`, `.gameAlreadyFinished`, `.columnFull`.
        return try await rpcSingle("play_connect_four_move", params: Params(pSessionId: sessionID, pColumn: column))
    }

    static func fetchGameMoves(sessionID: UUID) async throws -> [GameMove] {
        try await supabase
            .from("game_moves")
            .select()
            .eq("session_id", value: sessionID)
            .order("move_number")
            .execute()
            .value
    }

    /// Moves as they land, for a board both people are looking at.
    ///
    /// Its own subscription rather than an addition to `subscribeToGameSession`: that one watches
    /// `game_responses`, which a turn-based game never writes, and every other game would pay for a
    /// channel filter it has no use for.
    /// One past Connect 4 game, as the entry screen lists it.
    struct ConnectFourHistoryEntry: Identifiable, Hashable, Decodable {
        let id: UUID
        let status: GameSessionStatus
        let createdAt: Date
        let updatedAt: Date
        let completedAt: Date?
        /// Who won. Nil for a draw, and for a game ended or expired without a result.
        let winnerID: UUID?
        /// "win", a kind of draw, or nil for a game still going or closed without a result
        /// (20261015000100).
        let outcome: String?

        enum CodingKeys: String, CodingKey {
            case id, status, outcome
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case completedAt = "completed_at"
            case winnerID = "winner_id"
        }

        var isFinished: Bool { status == .completed || status == .abandoned || status == .archived }
        var endedAt: Date { completedAt ?? updatedAt }
    }

    /// The couple's recent Connect 4 games, newest first. One query: the outcome is stored on the
    /// session when the game ends, so nothing has to be replayed to list who won.
    static func fetchConnectFourHistory(limit: Int = 30) async throws -> [ConnectFourHistoryEntry] {
        try await supabase
            .from("game_sessions")
            .select("id, status, created_at, updated_at, completed_at, winner_id, outcome")
            .eq("game_type", value: GameType.connectFour.rawValue)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    static func subscribeToGameMoves(sessionID: UUID) -> (channel: RealtimeChannelV2, stream: AsyncStream<Void>) {
        signalStream(channelName: "game_moves_\(sessionID.uuidString)", changes: [
            .insert("game_moves", filter: .eq("session_id", value: sessionID.uuidString)),
            // The session row too: it is what says the game is over, and the move that ended it
            // was the partner's — so this device never saw the RPC's answer.
            .update("game_sessions", filter: .eq("id", value: sessionID.uuidString)),
        ])
    }

    /// Every finished sudoku solve visible to this account, flattened for `SudokuStats`.
    ///
    /// Three queries whatever the history's size, rather than a session detail each: the existing
    /// `fetchGameSession(id:)` is per-id, and stats are all-time by nature, so fetching them that
    /// way would grow a round trip per puzzle ever played.
    ///
    /// Times are read with `SudokuPlayState.summary` rather than `decoded`, which would need each
    /// puzzle regenerated from its `content_id` purely to re-impose givens on entries nothing here
    /// looks at. Anything that fails to parse — a payload from a future version, most plausibly —
    /// is skipped rather than counted as a zero, which would otherwise install an unbeatable best
    /// time of 0:00.
    ///
    /// RLS still decides what comes back: a partner's response is only visible once both have
    /// answered, so an unfinished puzzle of theirs cannot appear here.
    static func fetchSudokuSolves(limit: Int = 500) async throws -> [SudokuSolve] {
        struct SudokuSessionIDRow: Decodable { var id: UUID }

        let sessionRows: [SudokuSessionIDRow] = try await supabase
            .from("game_sessions")
            .select("id")
            .eq("game_type", value: GameType.sudoku.rawValue)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        let sessionIDs = sessionRows.map(\.id)
        guard !sessionIDs.isEmpty else { return [] }

        let roundRows: [GameSessionRoundRow] = try await supabase
            .from("game_session_rounds")
            .select()
            .in("session_id", values: sessionIDs)
            .execute()
            .value
        // A sudoku session has exactly one round, so this is a lookup rather than a grouping.
        var difficultyBySession: [UUID: SudokuDifficulty] = [:]
        for row in roundRows {
            guard let difficulty = row.difficulty else { continue }
            difficultyBySession[row.sessionId] = difficulty
        }

        let responseRows: [GameResponseRow] = try await supabase
            .from("game_responses")
            .select()
            .in("session_id", values: sessionIDs)
            .execute()
            .value

        return responseRows.compactMap { row in
            let response = row.toModel()
            guard let difficulty = difficultyBySession[response.sessionID],
                  let summary = SudokuPlayState.summary(from: response.answerValue),
                  summary.isComplete
            else { return nil }
            return SudokuSolve(
                sessionID: response.sessionID,
                difficulty: difficulty,
                responderID: response.responderID,
                elapsed: summary.elapsed
            )
        }
    }
}
