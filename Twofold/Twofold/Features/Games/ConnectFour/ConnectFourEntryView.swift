//
//  ConnectFourEntryView.swift
//  Twofold
//
//  Connect 4's front door. No decks, no difficulties, no themes — one board per couple, so the only
//  thing to decide is whether to open it.
//
//  It exists rather than the hub card pushing straight in because starting is a round trip that can
//  refuse, and because a session should be created by somebody deciding to play rather than by
//  somebody browsing past. Tapping a card is not a decision to start a game the partner will then
//  be notified about.
//

import SwiftUI

struct ConnectFourEntryView: View {
    @Environment(AppModel.self) private var appModel

    @State private var isStarting = false
    @State private var route: StartedConnectFour?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("One board between you. Take turns dropping a disc — first to get four in a row, in any direction, wins.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                    .fixedSize(horizontal: false, vertical: true)

                howItLooks

                Text("Played a move at a time, whenever you each get to it — there's no clock. You'll be told when it's your turn.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .fixedSize(horizontal: false, vertical: true)

                startButton

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.heartRedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(GameType.connectFour.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { started in
            ConnectFourGameView(sessionID: started.id)
        }
    }

    /// A finished board rather than an empty one. "Four in a row" is quicker to see than to read,
    /// and an empty grid would be a picture of nothing.
    private var howItLooks: some View {
        ConnectFourBoardView(
            board: ConnectFourBoard(droppedColumns: [3, 2, 4, 2, 5, 1, 6]),
            myDisc: .first,
            isInteractive: false,
            onDrop: { _ in }
        )
        .accessibilityHidden(true)
    }

    private var startButton: some View {
        Button(action: start) {
            HStack(spacing: Theme.Spacing.xs) {
                if isStarting { ProgressView().controlSize(.small).tint(.white) }
                // Deliberately not "Start a game": only the server knows whether one is already
                // going, and a button promising a new board that hands back a half-played one is a
                // small lie told at the worst moment.
                Text("Play")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(Theme.primaryButtonGradient, in: Capsule())
        .foregroundStyle(.white)
        .disabled(isStarting)
    }

    private func start() {
        isStarting = true
        errorMessage = nil
        Task {
            defer { isStarting = false }
            do {
                let session = try await BackendService.startConnectFourSession()
                route = StartedConnectFour(id: session.sessionID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct StartedConnectFour: Identifiable, Hashable {
    let id: UUID
}

#Preview {
    NavigationStack { ConnectFourEntryView() }
        .environment(AppModel())
}
