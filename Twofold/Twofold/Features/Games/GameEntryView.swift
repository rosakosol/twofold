//
//  GameEntryView.swift
//  Twofold
//
//  Single choke point every game card routes through: starts a new session or resumes an
//  in-progress one, then routes to the right typed game view. No subscription check here —
//  `RootView` gates all of `MainTabView` (Games included) behind `AppModel.isSubscriptionActive`
//  before this screen is ever reachable, so a second, feature-local gate would just be
//  redundant (and, checking only local StoreKit, would have been wrong for a partner who
//  joined via invite and never purchased anything on their own Apple ID).
//

import SwiftUI

struct GameEntryView: View {
    let gameType: GameType

    @State private var errorMessage: String?
    @State private var sessionID: UUID?

    var body: some View {
        Group {
            if let errorMessage {
                errorState(errorMessage)
            } else if let sessionID {
                gameDestination(sessionID: sessionID)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(gameType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await startOrResume() }
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
                Task { await startOrResume() }
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

    /// Resumes an existing active/waiting session of this type if one exists, so re-tapping a
    /// game card doesn't fork a duplicate session.
    private func startOrResume() async {
        errorMessage = nil
        do {
            let existing = try await BackendService.fetchGameSessions()
            if let resumable = existing.first(where: { $0.gameType == gameType && ($0.status == .active || $0.status == .waitingForPartner) }) {
                sessionID = resumable.id
            } else {
                sessionID = try await BackendService.startGameSession(gameType: gameType)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
