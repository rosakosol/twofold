//
//  DeckEntryView.swift
//  Twofold
//
//  The deck-scoped equivalent of GameEntryView — same three-phase choke point (intro / resume /
//  play), but resumption is matched on `deckID` rather than `gameType`, since a couple can have
//  independent sessions for several decks that share the same underlying mechanic (e.g. two
//  different "This or That" decks in different topics are unrelated sessions). Reuses the exact
//  same 4 game views as regular sessions — a deck session is an ordinary GameSession under the
//  hood (see `start_deck_session`), just pre-populated from a curated content subset instead of a
//  random sample of the shared pool.
//

import SwiftUI

struct DeckEntryView: View {
    let deck: GameDeck

    @Environment(AppModel.self) private var appModel
    @State private var errorMessage: String?
    @State private var phase: Phase = .loading
    @State private var isStarting = false

    private enum Phase {
        case loading
        case intro(sessionID: UUID?, partnerAlreadyFinished: Bool, totalRounds: Int)
        case playing(sessionID: UUID)
    }

    var body: some View {
        Group {
            if let errorMessage {
                errorState(errorMessage)
            } else {
                switch phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .intro(let sessionID, let partnerAlreadyFinished, let totalRounds):
                    GameIntroView(
                        gameType: deck.gameType,
                        totalRounds: totalRounds,
                        topic: GameTopic(rawValue: deck.topic),
                        partnerAlreadyFinished: partnerAlreadyFinished,
                        partnerName: appModel.partner.name,
                        isStarting: isStarting,
                        onStart: { Task { await start(existingSessionID: sessionID) } }
                    )
                case .playing(let sessionID):
                    gameDestination(sessionID: sessionID)
                }
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(deck.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await determinePhase() }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.heartRed)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await determinePhase() }
            }
            .font(.headline)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func gameDestination(sessionID: UUID) -> some View {
        switch deck.gameType {
        case .travelTrivia: TravelTriviaGameView(sessionID: sessionID)
        case .moreLikely: WhosMoreLikelyGameView(sessionID: sessionID)
        case .thisOrThat: ThisOrThatGameView(sessionID: sessionID)
        case .discussBeforeTravelling: DiscussBeforeTravellingGameView(sessionID: sessionID)
        }
    }

    private func determinePhase() async {
        errorMessage = nil
        do {
            let existing = try await BackendService.fetchGameSessions()
            guard let resumable = existing.first(where: { $0.deckID == deck.id && ($0.status == .active || $0.status == .waitingForPartner) }) else {
                phase = .intro(sessionID: nil, partnerAlreadyFinished: false, totalRounds: 8)
                return
            }
            let detail = try await BackendService.fetchGameSession(id: resumable.id)
            let myAnswered = GameLogic.answeredRoundNumbers(responses: detail.responses, responderID: appModel.currentUser.id)
            if myAnswered.isEmpty {
                let partnerFinished = GameLogic.partnerProgress(responses: detail.responses, partnerID: appModel.partner.id, totalRounds: detail.session.totalRounds) == .finished
                phase = .intro(sessionID: resumable.id, partnerAlreadyFinished: partnerFinished, totalRounds: detail.session.totalRounds)
            } else {
                phase = .playing(sessionID: resumable.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func start(existingSessionID: UUID?) async {
        isStarting = true
        do {
            if let existingSessionID {
                phase = .playing(sessionID: existingSessionID)
            } else {
                let newSessionID = try await BackendService.startDeckSession(deckID: deck.id)
                phase = .playing(sessionID: newSessionID)
                Task { await appModel.refreshGameDecks() }
                Task { await BackendService.notifyPartner(event: .gameStarted, detail: deck.title) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isStarting = false
    }
}
