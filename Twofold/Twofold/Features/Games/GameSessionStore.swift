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
        let wasRevealed = isRevealed
        do {
            try await BackendService.submitGameResponse(sessionID: session.id, roundNumber: roundNumber, answerValue: answerValue, isCorrect: isCorrect)
            await refresh()
            // Only the submit that actually flips the session to completed notifies — the
            // partner who finished first already has `wasRevealed == true` never occurring on
            // their own subsequent submits (they have none left), so this can only fire once
            // per session, from whoever's answer was the couple's last one.
            if !wasRevealed, isRevealed {
                await BackendService.notifyPartner(event: .gameResultsReady)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
}
