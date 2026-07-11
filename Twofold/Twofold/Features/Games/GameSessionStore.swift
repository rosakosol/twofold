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
    /// Whatever's currently visible to the caller — RLS (not this store) is what hides a
    /// partner's response until both have answered a round.
    var responses: [GameResponse] = []
    var isLoading = false
    var errorMessage: String?

    private var channel: RealtimeChannelV2?

    var currentRound: GameSessionRound? {
        guard let session else { return nil }
        return rounds.first { $0.roundNumber == session.currentRound }
    }

    func myResponse(for round: GameSessionRound, myID: UUID) -> GameResponse? {
        responses.first { $0.roundNumber == round.roundNumber && $0.responderID == myID }
    }

    func partnerResponse(for round: GameSessionRound, myID: UUID) -> GameResponse? {
        responses.first { $0.roundNumber == round.roundNumber && $0.responderID != myID }
    }

    func visibility(for round: GameSessionRound, myID: UUID) -> RoundVisibility {
        GameLogic.visibility(myResponse: myResponse(for: round, myID: myID), partnerResponse: partnerResponse(for: round, myID: myID))
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

    /// Round number is passed explicitly (the view's own walk-through pointer) rather than
    /// read from `session.currentRound` — a resumed session's server-side "current round"
    /// only ever points at the first round still missing an answer, but the view may still be
    /// stepping through earlier already-revealed rounds the caller hasn't tapped past yet.
    @discardableResult
    func submit(roundNumber: Int, answerValue: String, isCorrect: Bool? = nil) async -> Bool {
        guard let session else { return false }
        do {
            try await BackendService.submitGameResponse(sessionID: session.id, roundNumber: roundNumber, answerValue: answerValue, isCorrect: isCorrect)
            await refresh()
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
