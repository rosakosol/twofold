//
//  GameSessionStore.swift
//  Twofold
//
//  The one reusable session engine every game view shares — loading, realtime, submitting,
//  and abandoning all live here so a future 5th game just adds a `GameType` case, a content
//  table, and a view that reads this same store, rather than rewriting session/reveal logic.
//

import Foundation
import Observation
import Supabase

@Observable
final class GameSessionStore {
    var session: GameSession?
    var rounds: [GameSessionRound] = []
    var roundContent: [UUID: GameRoundContent] = [:]
    /// Whatever's currently visible to the caller — RLS (not this store) is what hides the
    /// couple's responses entirely until the session is fully completed by both partners.
    var responses: [GameResponse] = []
    var isLoading = false
    var errorMessage: String?
    /// Mirrors `PendingGameResponseStore.forSession(session.id).count` — kept as its own stored
    /// property (rather than computed straight off the store) so reading it from a view actually
    /// participates in `@Observable` change tracking; the on-disk queue itself has no observation
    /// of its own.
    var pendingSyncCount = 0

    private var channel: RealtimeChannelV2?

    /// True once BOTH partners have answered every round — the single moment everything in
    /// `responses` becomes visible at once (see the RLS policy on `game_responses`), replacing
    /// the old per-round pairwise reveal.
    var isRevealed: Bool { session?.status == .completed }

    /// The next round *I* haven't answered yet — each partner walks straight through their own
    /// unanswered rounds at their own pace, never blocked on the other person mid-game.
    func nextUnansweredRound(myID: UUID) -> GameSessionRound? {
        let answered = GameLogic.answeredRoundNumbers(responses: responses, responderID: myID)
        return rounds.first { !answered.contains($0.roundNumber) }
    }

    func hasAnsweredAllRounds(myID: UUID) -> Bool {
        guard let session else { return false }
        return GameLogic.answeredRoundNumbers(responses: responses, responderID: myID).count >= session.totalRounds
    }

    func myResponse(for round: GameSessionRound, myID: UUID) -> GameResponse? {
        responses.first { $0.roundNumber == round.roundNumber && $0.responderID == myID }
    }

    func partnerResponse(for round: GameSessionRound, partnerID: UUID) -> GameResponse? {
        responses.first { $0.roundNumber == round.roundNumber && $0.responderID == partnerID }
    }

    func partnerProgress(partnerID: UUID) -> PartnerProgress {
        guard let session else { return .notStarted }
        return GameLogic.partnerProgress(responses: responses, partnerID: partnerID, totalRounds: session.totalRounds)
    }

    func content(for round: GameSessionRound) -> GameRoundContent? {
        roundContent[round.contentID]
    }

    /// Subscribes to realtime and re-fetches (never trusts the realtime payload itself) on
    /// every change — same idea as `FlightTrackingView.loadAndSubscribe()`, but split into its
    /// own method (call from a second, concurrent `.task`) so the view can render right after
    /// `load(sessionID:)` finishes instead of waiting on this call's infinite loop. Pair with
    /// `stopRealtime()` in `.onDisappear`.
    func subscribeRealtime(sessionID: UUID) async {
        let (channel, stream) = BackendService.subscribeToGameSession(id: sessionID)
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

    func load(sessionID: UUID) async {
        isLoading = true
        errorMessage = nil
        do {
            let detail = try await BackendService.fetchGameSession(id: sessionID)
            session = detail.session
            rounds = detail.rounds
            roundContent = detail.content
            responses = detail.responses
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        // Re-apply anything still sitting in the local offline queue for this session — covers
        // reopening a session that was answered offline and never got a chance to sync (app
        // backgrounded/killed before reconnecting), so those answers don't briefly vanish from
        // `responses` between this load and the next successful sync.
        let pending = PendingGameResponseStore.forSession(sessionID)
        pendingSyncCount = pending.count
        for item in pending {
            applyOptimistic(item)
        }
        if NetworkMonitor.shared.isConnected {
            await syncPendingResponses()
        }
    }

    func refresh() async {
        guard let session else { return }
        if let detail = try? await BackendService.fetchGameSession(id: session.id) {
            self.session = detail.session
            self.rounds = detail.rounds
            self.roundContent = detail.content
            self.responses = detail.responses
        }
    }

    @discardableResult
    func submit(roundNumber: Int, answerValue: String, isCorrect: Bool? = nil) async -> Bool {
        guard let session else { return false }
        guard NetworkMonitor.shared.isConnected else {
            queueOffline(sessionID: session.id, roundNumber: roundNumber, answerValue: answerValue, isCorrect: isCorrect)
            return true
        }
        let wasRevealed = isRevealed
        do {
            try await BackendService.submitGameResponse(sessionID: session.id, roundNumber: roundNumber, answerValue: answerValue, isCorrect: isCorrect)
            await refresh()
            // Only the submit that actually flips the session to completed notifies — the
            // partner who finished first already has `wasRevealed == true` never occurring on
            // their own subsequent submits (they have none left), so this can only fire once
            // per session, from whoever's answer was the couple's last one.
            if !wasRevealed, isRevealed {
                await BackendService.notifyPartner(event: .gameResultsReady, sessionID: session.id, gameType: session.gameType)
            }
            return true
        } catch {
            // `NetworkMonitor` said we were online a moment ago, but the request itself still
            // failed — almost certainly the connection dropping mid-flight rather than a real
            // server rejection (nothing about this insert is validated in a way the app's own UI
            // could trigger). Queue it exactly like the explicit-offline path instead of
            // stranding the tap behind `errorMessage` and losing it outright.
            queueOffline(sessionID: session.id, roundNumber: roundNumber, answerValue: answerValue, isCorrect: isCorrect)
            return true
        }
    }

    /// Saves an answer locally and reflects it in `responses` immediately, so `nextUnansweredRound`
    /// and every view reading this store see it exactly as if it had round-tripped to the server —
    /// this is what lets play continue uninterrupted while offline.
    private func queueOffline(sessionID: UUID, roundNumber: Int, answerValue: String, isCorrect: Bool?) {
        guard let myID = BackendService.currentUserID else { return }
        let pending = PendingGameResponse(sessionID: sessionID, roundNumber: roundNumber, responderID: myID, answerValue: answerValue, isCorrect: isCorrect)
        PendingGameResponseStore.add(pending)
        pendingSyncCount = PendingGameResponseStore.forSession(sessionID).count
        applyOptimistic(pending)
    }

    private func applyOptimistic(_ pending: PendingGameResponse) {
        guard !responses.contains(where: { $0.sessionID == pending.sessionID && $0.roundNumber == pending.roundNumber && $0.responderID == pending.responderID }) else { return }
        responses.append(GameResponse(id: pending.id, sessionID: pending.sessionID, roundNumber: pending.roundNumber, responderID: pending.responderID, answerValue: pending.answerValue, isCorrect: pending.isCorrect, createdAt: pending.queuedAt))
    }

    /// Drains the local offline queue for this session, in the order the answers were recorded —
    /// called once on `load(sessionID:)` (if already online) and again whenever `NetworkMonitor`
    /// reports a reconnect (see each typed game view's `.onChange(of:)`). A failed submit here is
    /// swallowed and the entry dropped rather than retried indefinitely: a repeat failure almost
    /// always means that round was already synced by an earlier pass (a duplicate insert is
    /// rejected by the same one-response-per-round-per-responder constraint `advance_game_session`
    /// relies on), not a transient issue worth blocking the rest of the queue over.
    func syncPendingResponses() async {
        guard let session else { return }
        let pending = PendingGameResponseStore.forSession(session.id)
        guard !pending.isEmpty else { return }
        let wasRevealed = isRevealed
        for item in pending {
            try? await BackendService.submitGameResponse(sessionID: item.sessionID, roundNumber: item.roundNumber, answerValue: item.answerValue, isCorrect: item.isCorrect)
            PendingGameResponseStore.remove(id: item.id)
        }
        pendingSyncCount = PendingGameResponseStore.forSession(session.id).count
        await refresh()
        if !wasRevealed, isRevealed {
            await BackendService.notifyPartner(event: .gameResultsReady, sessionID: session.id, gameType: session.gameType)
        }
    }

    func abandon() async {
        guard let session else { return }
        try? await BackendService.abandonGameSession(id: session.id)
        await refresh()
    }

    func markDiscussionRound(_ round: GameSessionRound, status: DiscussionRoundStatus) async {
        try? await BackendService.markDiscussionRound(roundID: round.id, status: status)
        await refresh()
    }

    /// Deletes only my own responses and drops the session back to `active` if it had already
    /// completed — the partner's answers are untouched. Works both pre-reveal (GameCompletionView,
    /// session already `active` since the partner isn't done) and post-reveal (GameResultsView,
    /// session `completed`); see `edit_my_game_responses`.
    func editMyAnswers() async {
        guard let session else { return }
        try? await BackendService.editMyGameResponses(sessionID: session.id)
        await refresh()
    }
}
