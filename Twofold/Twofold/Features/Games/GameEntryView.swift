//
//  GameEntryView.swift
//  Twofold
//
//  Single choke point every game card routes through. Decides between three phases: the intro
//  screen (brand new game, or an existing session I haven't answered anything in yet — covers
//  both "starting fresh" and "my partner already finished, ready?"), or straight into play if
//  I've already started answering my own rounds. No subscription check here — `RootView` gates
//  all of `MainTabView` (Games included) behind `AppModel.isSubscriptionActive` before this
//  screen is ever reachable, so a second, feature-local gate would just be redundant.
//

import SwiftUI

struct GameEntryView: View {
    let gameType: GameType

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
                        gameType: gameType,
                        totalRounds: totalRounds,
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
        .navigationTitle(gameType.displayName)
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
        switch gameType {
        case .travelTrivia: TravelTriviaGameView(sessionID: sessionID)
        case .moreLikely: WhosMoreLikelyGameView(sessionID: sessionID)
        case .thisOrThat: ThisOrThatGameView(sessionID: sessionID)
        case .discussBeforeTravelling: DiscussBeforeTravellingGameView(sessionID: sessionID)
        }
    }

    /// Finds a resumable session of this type (still checks the legacy `waitingForPartner`
    /// status too, for any pre-restructure rows that haven't received a new response since —
    /// the rewritten trigger only ever writes `active`/`completed` going forward). If I haven't
    /// answered anything in it yet, that's the intro screen's moment (whether it's genuinely
    /// new or my partner just got there first); otherwise I go straight back into play.
    private func determinePhase() async {
        errorMessage = nil
        do {
            let existing = try await BackendService.fetchGameSessions()
            guard let resumable = existing.first(where: { $0.gameType == gameType && ($0.status == .active || $0.status == .waitingForPartner) }) else {
                phase = .intro(sessionID: nil, partnerAlreadyFinished: false, totalRounds: gameType.defaultRoundCount)
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
                let newSessionID = try await BackendService.startGameSession(gameType: gameType)
                phase = .playing(sessionID: newSessionID)
                Task { await BackendService.notifyPartner(event: .gameStarted, detail: gameType.displayName) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isStarting = false
    }
}
