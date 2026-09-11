//
//  ChessGameStore.swift
//  Twofold
//
//  One board, two people, alternating — the same arrangement as Connect 4, with a harder game on it.
//
//  Nothing is kept on the device. The move log on the server *is* the state, and a local copy would
//  be a second answer to what is on the board. That also means chess needs a connection, and says
//  so rather than pretending otherwise.
//
//  ---------------------------------------------------------------------------
//  The board is replayed, never loaded
//  ---------------------------------------------------------------------------
//
//  `ChessKit.Board.state` is only meaningful after a move: at init it assesses the side that has
//  just moved rather than the side to move, so a checkmated position loaded from a FEN reports
//  `.active`. A board rebuilt from a stored position would therefore never notice that the game had
//  ended. See `ChessKitContractTests`, which pins both halves of that.
//
//  The server replays for the same conclusion by a different route — a position is only as
//  trustworthy as the moves that made it.
//

import ChessKit
import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class ChessGameStore {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let sessionID: UUID

    private(set) var phase: Phase = .loading
    private(set) var board = Board()
    private(set) var moves: [BackendService.GameMove] = []
    private(set) var initiatorID: UUID?
    private(set) var isFinished = false
    /// Set when the game ended without being played out — ended by a player, or expired after a
    /// fortnight. There is no winner in either, and the board is not the reason it stopped.
    private(set) var closedWithoutResult = false
    private(set) var isPlaying = false
    private(set) var rejection: String?

    /// The square the player has picked up, if any. Tap to select, tap again to move — a drag
    /// gesture on a 44pt square is a lot of ways to drop a queen somewhere unintended.
    var selected: Square?
    /// A move waiting on which piece to promote to. Held rather than applied, because promotion is
    /// a second decision and the board cannot finish the move without it.
    private(set) var pendingPromotion: (from: Square, to: Square)?

    private var responderID: UUID?
    private var channel: RealtimeChannelV2?

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    // MARK: - Whose game it is

    /// White is the initiator — the only ordering both devices can derive without being told, and
    /// the same rule the server applies.
    var myColor: Piece.Color? {
        guard let me = responderID, let initiatorID else { return nil }
        return me == initiatorID ? .white : .black
    }

    var sideToMove: Piece.Color { board.position.sideToMove }
    var isMyTurn: Bool { !isFinished && myColor != nil && myColor == sideToMove }

    /// Where the selected piece may legally go. Empty when nothing is selected or it is not this
    /// player's turn — the board should not offer destinations for a move that cannot be made.
    var legalDestinations: [Square] {
        guard let selected, isMyTurn else { return [] }
        return board.legalMoves(forPieceAt: selected)
    }

    /// The two squares of the last move, for the board to mark. On a game played across a day, the
    /// first question on opening it is always "what did they do".
    var lastMoveSquares: (from: Square, to: Square)? {
        guard let last = moves.last else { return nil }
        let text = last.move
        guard text.count >= 4 else { return nil }
        let from = Square(String(text.prefix(2)))
        let to = Square(String(text.dropFirst(2).prefix(2)))
        return (from, to)
    }

    var isInCheck: Bool {
        if case .check = board.state { return true }
        return false
    }

    /// The colour that was checkmated, once there is one.
    var checkmatedColor: Piece.Color? {
        if case .checkmate(let color) = board.state { return color }
        return nil
    }

    var didIWin: Bool? {
        guard let checkmatedColor, let myColor else { return nil }
        return checkmatedColor != myColor
    }

    var drawReason: Board.State.DrawReason? {
        if case .draw(let reason) = board.state { return reason }
        return nil
    }

    // MARK: - Loading

    func load() async {
        phase = .loading
        do {
            let detail = try await BackendService.fetchGameSession(id: sessionID)
            let fetched = try await BackendService.fetchGameMoves(sessionID: sessionID)

            responderID = BackendService.currentUserID
            initiatorID = detail.session.initiatorID
            apply(moves: fetched, status: detail.session.status)
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func apply(moves: [BackendService.GameMove], status: GameSessionStatus) {
        self.moves = moves
        board = Self.replay(moves)

        let isLive = status == .active || status == .waitingForPartner
        let boardEnded = Self.isTerminal(board.state)
        isFinished = !isLive || boardEnded
        closedWithoutResult = !isLive && !boardEnded
        selected = nil
    }

    /// Rebuilds the position by replaying the log.
    ///
    /// A move that will not play is the end of the replay rather than something to skip: the rest
    /// of the log describes a position that never existed, and a board built from half a game is
    /// one neither player has ever seen.
    private static func replay(_ moves: [BackendService.GameMove]) -> Board {
        var board = Board()
        for entry in moves {
            let text = entry.move
            guard text.count >= 4 else { break }
            let from = Square(String(text.prefix(2)))
            let to = Square(String(text.dropFirst(2).prefix(2)))
            guard let played = board.move(pieceAt: from, to: to) else { break }

            // The promotion piece rides in the fifth character ("a7a8q"). Without completing it the
            // board stays in `.promotion` and refuses every subsequent move.
            if let kindLetter = text.dropFirst(4).first, let kind = Self.promotionKind(kindLetter) {
                board.completePromotion(of: played, to: kind)
            }
        }
        return board
    }

    private static func promotionKind(_ letter: Character) -> Piece.Kind? {
        switch letter {
        case "q": .queen
        case "r": .rook
        case "b": .bishop
        case "n": .knight
        default: nil
        }
    }

    private static func isTerminal(_ state: Board.State) -> Bool {
        switch state {
        case .checkmate, .draw: true
        case .active, .check, .promotion: false
        }
    }

    // MARK: - Playing

    /// Picks a square up, or puts it down, or moves to it.
    func tap(_ square: Square) {
        guard isMyTurn, !isPlaying else { return }
        rejection = nil

        if let selected {
            if selected == square {
                self.selected = nil
                return
            }
            if board.legalMoves(forPieceAt: selected).contains(square) {
                beginMove(from: selected, to: square)
                return
            }
        }

        // Selecting one of your own pieces, and only one of yours: tapping the opponent's knight to
        // see where it could go is a feature of an analysis board, not of a game.
        if let piece = board.position.piece(at: square), piece.color == myColor {
            selected = square
        } else {
            selected = nil
        }
    }

    private func beginMove(from: Square, to: Square) {
        // A pawn reaching the last rank is two decisions, and the second one cannot be guessed:
        // under-promoting to a knight is a real move and defaulting to a queen would silently play
        // a different one.
        if let piece = board.position.piece(at: from),
           piece.kind == .pawn,
           to.rank == (piece.color == .white ? 8 : 1) {
            pendingPromotion = (from, to)
            return
        }
        Task { await send(from: from, to: to, promotion: nil) }
    }

    func choosePromotion(_ kind: Piece.Kind) {
        guard let pending = pendingPromotion else { return }
        pendingPromotion = nil
        let letter: String
        switch kind {
        case .queen: letter = "q"
        case .rook: letter = "r"
        case .bishop: letter = "b"
        case .knight: letter = "n"
        default: letter = "q"
        }
        Task { await send(from: pending.from, to: pending.to, promotion: letter) }
    }

    func cancelPromotion() {
        pendingPromotion = nil
        selected = nil
    }

    private func send(from: Square, to: Square, promotion: String?) async {
        isPlaying = true
        selected = nil
        defer { isPlaying = false }

        do {
            _ = try await BackendService.playChessMove(
                sessionID: sessionID,
                from: from.notation,
                to: to.notation,
                promotion: promotion
            )
            // Re-read rather than apply locally. The server decides whether that ended the game,
            // and this is also when a move the partner made a moment earlier arrives.
            await refresh()
        } catch let error as BackendError {
            rejection = error.errorDescription
            await refresh()
        } catch {
            rejection = error.localizedDescription
        }
    }

    private func refresh() async {
        guard let detail = try? await BackendService.fetchGameSession(id: sessionID),
              let fetched = try? await BackendService.fetchGameMoves(sessionID: sessionID)
        else { return }
        let wasFinished = isFinished
        apply(moves: fetched, status: detail.session.status)
        if !wasFinished, isFinished, !closedWithoutResult { await notifyPartnerOfResult() }
    }

    // MARK: - Live

    func subscribeRealtime() async {
        let (channel, stream) = BackendService.subscribeToGameMoves(sessionID: sessionID)
        self.channel = channel
        for await _ in stream {
            await refresh()
        }
    }

    func stopRealtime() {
        guard let channel else { return }
        Task { await BackendService.unsubscribe(channel) }
        self.channel = nil
    }

    /// Ends the game for both, without a winner — the same `abandon_game_session` every other game
    /// uses. Needed for the same reason Connect 4 needs it: expiry takes a fortnight, and one board
    /// per couple means until then they cannot start another.
    func endGame() async throws {
        try await BackendService.abandonGameSession(id: sessionID)
        await refresh()
    }

    /// Only from the device whose move ended it. The other learns from the session row, and both
    /// sending would be two pushes for one result.
    private func notifyPartnerOfResult() async {
        guard let me = responderID, moves.last?.playerID == me else { return }
        await BackendService.notifyPartner(
            event: .gameResultsReady,
            detail: GameType.chess.displayName,
            sessionID: sessionID,
            gameType: .chess
        )
    }

    func nudgePartner() async {
        await BackendService.notifyPartner(
            event: .gameReminder,
            detail: GameType.chess.displayName,
            sessionID: sessionID,
            gameType: .chess
        )
    }
}
