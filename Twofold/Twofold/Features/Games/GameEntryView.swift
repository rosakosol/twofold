//
//  GameEntryView.swift
//  Twofold
//
//  Single choke point every game card routes through: checks the Plus/Premium subscription
//  gate, then starts a new session or resumes an in-progress one, then routes to the right
//  typed game view. Subscription check follows the same per-view SubscriptionStore instance
//  convention PaywallView already uses — there's no app-wide shared subscription state.
//

import SwiftUI

struct GameEntryView: View {
    let gameType: GameType

    @State private var subscriptionStore = SubscriptionStore()
    @State private var hasCheckedSubscription = false
    @State private var isStarting = false
    @State private var errorMessage: String?
    @State private var sessionID: UUID?
    @State private var showingPaywall = false

    var body: some View {
        Group {
            if !hasCheckedSubscription || isStarting {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !subscriptionStore.isSubscribed {
                lockedState
            } else if let errorMessage {
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
        .task {
            await subscriptionStore.loadProducts()
            hasCheckedSubscription = true
            if subscriptionStore.isSubscribed {
                await startOrResume()
            }
        }
        .sheet(isPresented: $showingPaywall) {
            NavigationStack { PaywallView() }
        }
    }

    private var lockedState: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle().fill(Theme.skyBlue.opacity(0.15))
                Image(systemName: "lock.fill").foregroundStyle(Theme.skyBlue)
            }
            .frame(width: 56, height: 56)

            Text("Unlock with Twofold Plus")
                .font(.title3.weight(.bold))
            Text("Couple games are part of Twofold Plus — unlock 500+ games and questions, unlimited memories, and more.")
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)

            Button {
                showingPaywall = true
            } label: {
                Text("See Twofold Plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .background(Theme.primaryButtonGradient, in: Capsule())
            .foregroundStyle(.white)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        isStarting = true
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
        isStarting = false
    }
}
