//
//  ChessGameView.swift
//  Twofold
//
//  The play screen: whose turn it is, the board, and what happened.
//

import ChessKit
import PostHog
import SwiftUI

struct ChessGameView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var store: ChessGameStore
    @State private var isNudging = false
    @State private var showingNudgeSent = false
    @State private var confirmingEnd = false
    @State private var endFailed: String?
    @State private var confettiTrigger = false
    @State private var celebratedSession: UUID?

    init(sessionID: UUID) {
        _store = State(initialValue: ChessGameStore(sessionID: sessionID))
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            switch store.phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                GameErrorState(message: message)
                    .padding(Theme.Spacing.lg)
            case .ready:
                content
            }

            ConfettiBurstView(trigger: confettiTrigger)
        }
        .navigationTitle(GameType.chess.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.phase == .ready && !store.isFinished {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) { confirmingEnd = true } label: {
                            Label("End this game", systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("End this game?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End it", role: .destructive) { endGame() }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("This ends it for both of you, with no winner, and clears the board so you can start a new game. \(appModel.partner.name) will see that it ended.")
        }
        .alert("Couldn't end the game", isPresented: .constant(endFailed != nil)) {
            Button("OK") { endFailed = nil }
        } message: {
            Text(endFailed ?? "")
        }
        .alert("Nudge sent", isPresented: $showingNudgeSent) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(appModel.partner.name) has been told it's their move.")
        }
        .sheet(isPresented: .constant(store.pendingPromotion != nil)) {
            ChessPromotionSheet(
                color: store.myColor ?? .white,
                onChoose: { store.choosePromotion($0) },
                onCancel: { store.cancelPromotion() }
            )
            .presentationDetents([.height(240)])
        }
        .task(id: store.sessionID) { await store.load() }
        .task(id: store.sessionID) { await store.subscribeRealtime() }
        // Only a win this player had. Confetti over a loss congratulates somebody for being beaten,
        // and a draw is not a result to throw anything at either.
        .onChange(of: store.isFinished, initial: true) { _, finished in
            guard finished, store.didIWin == true, celebratedSession != store.sessionID else { return }
            celebratedSession = store.sessionID
            confettiTrigger.toggle()
        }
        .sensoryFeedback(.success, trigger: confettiTrigger)
        // A tap for every move that lands, either player's — on a board you are both watching, the
        // partner's move arriving is the event worth feeling.
        .sensoryFeedback(.impact(weight: .light), trigger: store.moves.count)
        .onDisappear { store.stopRealtime() }
        .postHogScreenView("Games: Chess")
    }

    private var content: some View {
        VStack(spacing: Theme.Spacing.md) {
            turnBanner

            ChessBoardView(
                board: store.board,
                myColor: store.myColor,
                selected: store.selected,
                legalDestinations: store.legalDestinations,
                lastMove: store.lastMoveSquares,
                isInteractive: store.isMyTurn && !store.isPlaying,
                onTap: { store.tap($0) }
            )
            .padding(.horizontal, Theme.Spacing.md)
            .opacity(store.isFinished || store.isMyTurn ? 1 : 0.8)

            if store.isFinished {
                resultCard.padding(.horizontal, Theme.Spacing.md)
            } else if !store.isMyTurn {
                nudgeButton
            }

            if let rejection = store.rejection {
                Text(rejection)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.heartRedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.md)
    }

    @ViewBuilder
    private var turnBanner: some View {
        if !store.isFinished {
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(store.sideToMove == .white ? ChessBoardView.whitePiece : ChessBoardView.blackPiece)
                    .overlay(Circle().strokeBorder(Theme.subtleInk.opacity(0.5), lineWidth: 1))
                    .frame(width: 14, height: 14)
                Text(store.isMyTurn ? "Your move" : "\(appModel.partner.name)'s move")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                // Said in words as well as shown on the board. A red square is easy to miss on a
                // screen you have just opened, and being in check is the one thing you must not.
                if store.isInCheck {
                    Text("Check")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.heartRedText)
                }
                if store.isPlaying { ProgressView().controlSize(.small) }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var resultCard: some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: resultIcon)
                    .font(.largeTitle)
                    .foregroundStyle(store.didIWin == true ? Theme.leafGreen : Theme.subtleInk)
                Text(resultTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text(resultDetail)
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var resultIcon: String {
        if store.closedWithoutResult { return "flag.slash" }
        if store.checkmatedColor != nil { return store.didIWin == true ? "trophy.fill" : "hands.clap.fill" }
        return "equal.circle.fill"
    }

    private var resultTitle: String {
        if store.closedWithoutResult { return "This game ended" }
        if store.checkmatedColor != nil {
            return store.didIWin == true ? "Checkmate — you won" : "Checkmate — \(appModel.partner.name) won"
        }
        return "A draw"
    }

    /// Draws are named by their reason rather than all called "a draw". "You repeated the position
    /// three times" and "neither of you has enough left to mate" are different games, and a player
    /// who is not told which will not know what happened.
    private var resultDetail: String {
        if store.closedWithoutResult {
            return "It was ended or left too long, so there's no winner. Start a new one from the games list."
        }
        if store.checkmatedColor != nil {
            return store.didIWin == true
                ? "Start another from the games list."
                : "Start another from the games list."
        }
        switch store.drawReason {
        case .stalemate: return "Stalemate — no legal move, and not in check. Start another from the games list."
        case .insufficientMaterial: return "Neither of you has enough left to finish it. Start another from the games list."
        case .repetition: return "The same position three times over. Start another from the games list."
        case .fiftyMoves: return "Fifty moves with no capture and no pawn moved. Start another from the games list."
        case .agreement, .none: return "Start another from the games list."
        }
    }

    private var nudgeButton: some View {
        Button {
            isNudging = true
            Task {
                await store.nudgePartner()
                isNudging = false
                showingNudgeSent = true
            }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                if isNudging { ProgressView().controlSize(.small) }
                Text(isNudging ? "Sending…" : "Nudge \(appModel.partner.name)")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.skyBlueText)
        .disabled(isNudging)
    }

    private func endGame() {
        Task {
            do {
                try await store.endGame()
                dismiss()
            } catch {
                endFailed = error.localizedDescription
            }
        }
    }
}

/// Which piece a pawn becomes.
///
/// A sheet rather than a default, because under-promoting is a real move: a knight is occasionally
/// the only piece that mates, and a board that quietly queened for you would have played something
/// else entirely.
struct ChessPromotionSheet: View {
    let color: Piece.Color
    let onChoose: (Piece.Kind) -> Void
    let onCancel: () -> Void

    private let choices: [Piece.Kind] = [.queen, .rook, .bishop, .knight]

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Promote to")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(choices, id: \.self) { kind in
                    Button {
                        onChoose(kind)
                    } label: {
                        Text(ChessBoardView.glyph(for: kind))
                            .font(.system(size: 44))
                            .foregroundStyle(color == .white ? ChessBoardView.whitePiece : ChessBoardView.blackPiece)
                            .shadow(color: color == .white ? .black.opacity(0.45) : .white.opacity(0.25), radius: 0.6)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ChessBoardView.name(for: kind))
                }
            }

            Button("Cancel", action: onCancel)
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundGradient)
        // The move is not sent until a piece is chosen, so dismissing by swipe has to cancel it —
        // otherwise the pawn sits on the last rank and the board refuses every later move.
        .interactiveDismissDisabled(false)
    }
}
