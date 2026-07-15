//
//  GameHistoryView.swift
//  Twofold
//
//  Completed sessions, reachable from the Games hub. Tapping a row reopens the same typed
//  game view used for live play — each one checks `GameSessionStore.isRevealed` first and
//  routes straight to `GameResultsView` for a completed session, so no separate read-only
//  code path is needed here.
//

import SwiftUI

struct GameHistoryView: View {
    @Environment(AppModel.self) private var appModel
    @State private var sessions: [GameSession] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: Theme.Spacing.sm) {
                    GameErrorState(message: errorMessage)
                    Button("Try again") { Task { await load() } }
                }
            } else if sessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(sessions) { session in
                            NavigationLink {
                                gameDestination(session: session)
                            } label: {
                                historyRow(session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Past games")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .task { await appModel.loadGameDecksIfNeeded() }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundStyle(Theme.subtleInk)
            Text("No completed games yet")
                .font(.headline)
            Text("Finish a game together and it'll show up here.")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func historyRow(_ session: GameSession) -> some View {
        SectionCard {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: session.gameType.iconGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: session.gameType.icon).foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.gameType.displayName).font(.subheadline.weight(.semibold))
                    if let completedAt = session.completedAt {
                        Text(completedAt, format: .dateTime.day().month(.abbreviated).year())
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
            }
        }
    }

    @ViewBuilder
    private func gameDestination(session: GameSession) -> some View {
        let deck = session.deckID.flatMap { deckID in appModel.gameDecks?.first(where: { $0.id == deckID }) }
        gameDestinationView(gameType: session.gameType, sessionID: session.id, title: deck?.title, topic: deck?.topic)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let all = try await BackendService.fetchGameSessions(status: .completed)
            sessions = GameLogic.completedSessionsOnly(all)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        GameHistoryView()
    }
    .environment(AppModel())
}
