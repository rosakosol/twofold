//
//  ConnectFourGameStore.swift
//  Twofold
//
//  One board, two people, alternating.
//
//  Unlike every other game here, nothing is kept on the device. The other four write their progress
//  to `PuzzleProgressCache` because their state is private until they finish; this board is shared,
//  and the move log on the server *is* the state. A local copy would be a second answer to "what is
//  on the board", and the one that can disagree is the one somebody is looking at.
//
//  Which also means this is the first game here that genuinely needs a connection. It says so
//  rather than pretending otherwise.
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class ConnectFourGameStore {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let sessionID: UUID

    private(set) var phase: Phase = .loading
    private(set) var board = ConnectFourBoard()
    private(set) var moves: [BackendService.GameMove] = []
    /// Who started, and therefore who plays `.first`. Both devices need this to colour the board
    /// the same way round.
    private(set) var initiatorID: UUID?
    private(set) var isFinished = false
    /// Set while a move is in flight, so a second tap cannot send a second disc.
    private(set) var isPlaying = false
    /// Why the last tap did nothing, for the screen to say so and then forget.
    private(set) var rejection: String?
    /// The column this player last dropped into, for the board to animate it.
    private(set) var lastMoveColumn: Int?

    private var responderID: UUID?
    private var channel: RealtimeChannelV2?

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    // MARK: - Whose game it is

    var myDisc: ConnectFourBoard.Disc? {
        guard let me = responderID, let initiatorID else { return nil }
        return me == initiatorID ? .first : .second
    }

    /// Whose turn it is, derived from the move count exactly as the server derives it. Two copies
    /// of the same rule, and the server's is the one that decides — see `ConnectFourBoard`.
    var currentDisc: ConnectFourBoard.Disc { moves.count % 2 == 0 ? .first : .second }

    var isMyTurn: Bool { !isFinished && myDisc != nil && myDisc == currentDisc }

    /// The winning disc, once there is one.
    var winner: ConnectFourBoard.Disc? { board.winner }
    var didIWin: Bool? {
        guard let winner, let myDisc else { return nil }
        return winner == myDisc
    }
    var isDraw: Bool { board.isDraw }

    // MARK: - Loading

    func load() async {
        phase = .loading
        do {
            let detail = try await BackendService.fetchGameSession(id: sessionID)
            let fetched = try await BackendService.fetchGameMoves(sessionID: sessionID)

            responderID = BackendService.currentUserID
            initiatorID = detail.session.initiatorID
            apply(moves: fetched, sessionCompleted: detail.session.status == .completed)
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func apply(moves: [BackendService.GameMove], sessionCompleted: Bool) {
        self.moves = moves
        // Replayed from the log every time rather than patched incrementally. A board built by
        // applying deltas to itself is a board that can drift from the log it came from, and there
        // are only ever 42 moves to replay.
        board = ConnectFourBoard(droppedColumns: moves.compactMap { Int($0.move) })
        // Either is enough: the session row says so, and so does the board. Trusting only the
        // session would leave the last move's result invisible until that row's update arrived.
        isFinished = sessionCompleted || board.isFinished
    }

    // MARK: - Playing

    func play(column: Int) async {
        guard !isPlaying, isMyTurn, board.landingRow(in: column) != nil else { return }
        isPlaying = true
        rejection = nil
        defer { isPlaying = false }

        do {
            _ = try await BackendService.playConnectFourMove(sessionID: sessionID, column: column)
            lastMoveColumn = column
            // Re-read rather than assume. The server decides whether that move ended the game, and
            // this is also the moment a move the partner made a fraction earlier arrives.
            await refresh()
        } catch let error as BackendError {
            // The three named outcomes are what a shared board does when two people are quick:
            // saying them plainly beats an error dialog. Whatever the board really looks like
            // arrives with the refresh.
            rejection = error.errorDescription
            await refresh()
        } catch {
            rejection = error.localizedDescription
        }
    }

    /// Re-reads the moves and the session.
    ///
    /// Both, because the two answer different questions: the moves are the board, and the session
    /// row is what says the game is over when the move that ended it was the partner's — this
    /// device never saw that RPC's reply.
    private func refresh() async {
        guard let detail = try? await BackendService.fetchGameSession(id: sessionID),
              let fetched = try? await BackendService.fetchGameMoves(sessionID: sessionID)
        else { return }
        let wasFinished = isFinished
        apply(moves: fetched, sessionCompleted: detail.session.status == .completed)
        if !wasFinished, isFinished { await notifyPartnerOfResult() }
    }

    // MARK: - Live

    /// Subscribes to the move log, so the partner's disc lands on this board as they drop it.
    ///
    /// Call from a `.task` of its own — this loops until cancelled. Pair with `stopRealtime()`.
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

    /// Tells the partner the game is over.
    ///
    /// Only from the device whose move ended it — `refresh()` calls this on the transition, and the
    /// other device learns from the session row rather than from its own move. Both would otherwise
    /// send, and the couple would get two pushes for one result.
    private func notifyPartnerOfResult() async {
        guard let me = responderID, moves.last?.playerID == me else { return }
        await BackendService.notifyPartner(
            event: .gameResultsReady,
            detail: GameType.connectFour.displayName,
            sessionID: sessionID,
            gameType: .connectFour
        )
    }

    /// Tells the partner it is their move.
    ///
    /// Deliberately not sent on every turn — a push per disc would be a conversation conducted
    /// entirely in notifications. The screen offers it as a nudge, the way the other games do.
    func nudgePartner() async {
        await BackendService.notifyPartner(
            event: .gameReminder,
            detail: GameType.connectFour.displayName,
            sessionID: sessionID,
            gameType: .connectFour
        )
    }
}
