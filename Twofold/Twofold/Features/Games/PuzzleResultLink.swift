//
//  PuzzleResultLink.swift
//  Twofold
//
//  The part of a puzzle screen that talks to the session, shared by Sudoku, Word Guess and Word
//  Search (GAME-15).
//
//  Each of the three used to carry its own copy of the same machinery: who is answering, whether
//  the one result has gone, sending it and reacting to what came back, the push that tells the
//  partner, realtime, and the reminder. The submit-once bug had to be fixed three times because of
//  it. What stays with each store is what is genuinely its own — the play, the device cache, and
//  how to read the partner's half of the session.
//
//  The store tells the link how to re-read the partner (`refreshPartner`) and whether their result
//  is in (`partnerHasFinished`); the link calls those at the moments it used to be each store's job
//  to remember to.
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class PuzzleResultLink {
    let sessionID: UUID
    let gameType: GameType
    /// The result on its way to the server. See `PuzzleResult`.
    let result: PuzzleResult
    /// A finished result the server does not have yet — what the pending banner and the "saved on
    /// this phone" copy show.
    var isPending: Bool { result.isPending }

    /// Who is answering, read when the puzzle loads.
    @ObservationIgnored private(set) var responderID: UUID?
    /// The one result has been sent, or the server already had it. Never sent twice.
    @ObservationIgnored private(set) var hasSubmitted = false
    /// The result's one send while it is in flight, so a retry or "Play another" can wait for it.
    @ObservationIgnored private var submission: Task<Void, Never>?
    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private let backend: any PuzzleSessionBackend

    /// Re-reads the store's view of the partner's half of the session. Set by the store.
    @ObservationIgnored var refreshPartner: @MainActor () async -> Void = {}
    /// Whether the partner's result is visible, which can only happen once both are in (RLS) — so
    /// it decides whether the push says "your partner finished" or "results are ready".
    @ObservationIgnored var partnerHasFinished: @MainActor () -> Bool = { false }

    /// True while a reminder push is on its way.
    private(set) var isSendingReminder = false

    enum ReminderResult {
        case sent
        /// Offline, or the server said no: nothing reached the partner.
        case failed
    }

    /// How the last reminder went. Drives the alert, which says which.
    var reminderResult: ReminderResult?

    init(
        sessionID: UUID,
        gameType: GameType,
        backend: any PuzzleSessionBackend,
        queue: any GameResponseQueue
    ) {
        self.sessionID = sessionID
        self.gameType = gameType
        self.backend = backend
        self.result = PuzzleResult(sessionID: sessionID, gameType: gameType, backend: backend, queue: queue)
    }

    // MARK: - Loading

    /// Notes who is answering. Called first thing in a load, before anything else is decided.
    func begin(responderID: UUID?) {
        self.responderID = responderID
    }

    /// What the loaded session says about this player's result: the server has it or it does not.
    func noteServerHasResult(_ serverHasIt: Bool) {
        hasSubmitted = serverHasIt
        if serverHasIt, let responderID { result.noteDelivered(responderID: responderID) }
    }

    /// A refreshed session: if this player's result is in it, nothing is pending any more,
    /// however it got there.
    func noteDelivered(in detail: BackendService.GameSessionDetail) {
        guard let responderID else { return }
        if detail.responses.contains(where: { $0.responderID == responderID }) {
            result.noteDelivered(responderID: responderID)
        }
    }

    /// The session was ended elsewhere: any unsent result goes with it.
    func discard() {
        if let responderID { result.discard(responderID: responderID) }
    }

    // MARK: - Sending

    /// The one write to `game_responses` the puzzle makes. Queued before it is sent, so a send
    /// that fails is kept and tried again — see `PuzzleResult`.
    func send(encoded: String, isCorrect: Bool?, notifyDetail: String?) {
        guard !hasSubmitted, let me = responderID else { return }
        hasSubmitted = true
        submission = Task {
            let outcome = await result.send(encoded: encoded, isCorrect: isCorrect, notifyDetail: notifyDetail, responderID: me)
            await handle(outcome, notifyDetail: notifyDetail)
        }
    }

    /// Waits for the result's send, if one is in flight.
    func waitForSend() async {
        await submission?.value
    }

    /// Tries the result again if it is still waiting. The screen calls this, through its store, on
    /// reconnecting and on returning to the foreground.
    func retryPending(notifyDetail: String?) async {
        guard let me = responderID else { return }
        await submission?.value
        guard let outcome = await result.resendIfQueued(responderID: me) else {
            // Nothing left to send — it may have gone from `GameResponseOutbox` meanwhile, so
            // the partner's side is worth a fresh look.
            await refreshPartner()
            return
        }
        await handle(outcome, notifyDetail: notifyDetail)
    }

    private func handle(_ outcome: PuzzleResult.Outcome, notifyDetail: String?) async {
        switch outcome {
        case .sent:
            // If they finished first, their response was invisible until this insert — RLS only
            // reveals it once both sides have answered. Realtime would echo this same insert
            // back and trigger the read anyway, but that leaves the comparison depending on a
            // live socket to show a result both halves of which are already on the server.
            await refreshPartner()
            await notifyPartnerOfResult(notifyDetail: notifyDetail)
        case .pending:
            // Kept on the device and in the queue. The screen says so while `isPending`.
            break
        case .refused:
            // Almost always because the session was ended meanwhile; this read is what shows it.
            await refreshPartner()
        }
    }

    /// Tells the other side the puzzle is done — the same two pushes the deck games send from
    /// `GameSessionStore.performSubmit`, which the puzzles do not go through.
    ///
    /// Which of the two goes out is decided by the `refreshPartner()` that ran just above. Their
    /// result being visible at all means both responses are in, since RLS reveals a partner's row
    /// only once both sides have written one.
    ///
    /// Sent for a solo player too, exactly as the other games do: `couple_id` is null,
    /// `notify-couple-event` finds no couple and returns without sending anything.
    private func notifyPartnerOfResult(notifyDetail: String?) async {
        await backend.notifyPartner(
            event: partnerHasFinished() ? .gameResultsReady : .gamePartnerFinished,
            detail: notifyDetail,
            sessionID: sessionID,
            gameType: gameType
        )
    }

    // MARK: - The partner's side

    /// Subscribes to the session and re-reads the partner on every change, so a result that lands
    /// while the screen is open becomes the comparison without it being reopened.
    ///
    /// Call from a `.task` of its own — this loops until cancelled, so sharing the load's task
    /// would mean the board never rendered. Pair with `stopRealtime()`.
    func subscribeRealtime() async {
        let (channel, stream) = BackendService.subscribeToGameSession(id: sessionID)
        self.channel = channel
        for await _ in stream {
            await refreshPartner()
        }
    }

    func stopRealtime() {
        guard let channel else { return }
        Task { await BackendService.unsubscribe(channel) }
        self.channel = nil
    }

    /// The same `gameReminder` push the other games send — it is the identical situation, and a
    /// second notification type saying the same thing is a second thing to keep in step with the
    /// copy.
    ///
    /// `detail` lands inside quotation marks in the push (`wants you to complete "Hard Sudoku"`),
    /// so callers pass a name rather than nil.
    ///
    /// Returns the send, so a caller (a test) can wait for it.
    @discardableResult
    func remindPartner(detail: String) -> Task<Void, Never> {
        isSendingReminder = true
        return Task {
            let sent = await backend.sendGameReminder(detail: detail, sessionID: sessionID, gameType: gameType)
            isSendingReminder = false
            reminderResult = sent ? .sent : .failed
        }
    }
}
