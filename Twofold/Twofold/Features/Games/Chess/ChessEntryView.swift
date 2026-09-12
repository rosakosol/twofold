//
//  ChessEntryView.swift
//  Twofold
//
//  Chess's front door. One board per couple, so the only thing to decide is whether to open it.
//
//  The lock here is only so the screen can show one and open the paywall instead of starting a call
//  that would be refused; `start_chess_session` enforces it for real.
//

import ChessKit
import SwiftUI

struct ChessEntryView: View {
    @Environment(AppModel.self) private var appModel

    @Environment(\.dismiss) private var dismiss

    @State private var isStarting = false
    @State private var route: StartedChess?
    @State private var showingPaywall = false
    @State private var errorMessage: String?
    @State private var records: [GameRecord] = []

    private var isPremium: Bool { appModel.subscriptionTier == "premium" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("One board between you, played a move at a time. There's no clock — take as long as you like, and you'll be told when it's your turn.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                    .fixedSize(horizontal: false, vertical: true)

                // No bests for a board game: there is no time or score to keep, only the record.
                GameRecordCard(
                    records: records.filter { $0.gameType == .chess },
                    partnerName: appModel.partner.name,
                    formatBest: nil
                )

                ChessBoardView(
                    board: Self.illustration,
                    myColor: .white,
                    selected: nil,
                    legalDestinations: [],
                    lastMove: nil,
                    isInteractive: false,
                    onTap: { _ in }
                )
                .accessibilityHidden(true)

                if isPremium {
                    startButton
                } else {
                    premiumCard
                }

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
        .navigationTitle(GameType.chess.displayName)
        .navigationBarTitleDisplayMode(.inline)
        // Reloaded every time the screen appears: coming back after a game is exactly when the
        // record has changed.
        .task { records = await BackendService.fetchGameRecords() }
        // Leaving the board goes back to the games list, not to here.
        //
        // This screen's whole job is starting or resuming a game. Once one is running it has
        // nothing left to offer, so landing on it after backing out of a live board means being
        // shown the door you just came through and pressing back a second time. `route` returning
        // to nil is the board closing, which is the moment to get out of the way.
        .onChange(of: route) { previous, current in
            if previous != nil, current == nil { dismiss() }
        }
        .navigationDestination(item: $route) { started in
            ChessGameView(sessionID: started.id)
        }
        .sheet(isPresented: $showingPaywall) {
            NavigationStack { PaywallView(initialTier: .premium) }
        }
    }

    /// A few moves in rather than the starting position — a board nobody has touched is a picture
    /// of nothing, and this one shows what the pieces look like.
    private static var illustration: Board {
        var board = Board()
        for move in [(Square.e2, Square.e4), (.e7, .e5), (.g1, .f3), (.b8, .c6), (.f1, .c4)] {
            board.move(pieceAt: move.0, to: move.1)
        }
        return board
    }

    private var startButton: some View {
        Button(action: start) {
            HStack(spacing: Theme.Spacing.xs) {
                if isStarting { ProgressView().controlSize(.small).tint(.white) }
                // Not "Start a game": only the server knows whether one is already going, and a
                // button promising a new board that hands back a half-played one is a small lie
                // told at the worst moment.
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

    private var premiumCard: some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.subtleInk)
                Text("Chess is part of Premium")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("One subscription covers you both, so only one of you needs it.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("See Premium") { showingPaywall = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.skyBlueText)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func start() {
        isStarting = true
        errorMessage = nil
        Task {
            defer { isStarting = false }
            do {
                let session = try await BackendService.startChessSession()
                route = StartedChess(id: session.sessionID)
            } catch BackendError.chessRequiresPremium {
                // The client thought they were Premium and the server disagreed — a lapsed
                // subscription the app has not noticed yet. The paywall is the useful answer.
                showingPaywall = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct StartedChess: Identifiable, Hashable {
    let id: UUID
}

#Preview {
    NavigationStack { ChessEntryView() }
        .environment(AppModel())
}
