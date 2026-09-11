//
//  ConnectFourGameView.swift
//  Twofold
//
//  The play screen: whose turn it is, the board, and what happened.
//
//  The turn line sits above the board rather than below it. It is the thing that changes while you
//  are not looking, and it is the reason to have opened the screen at all.
//

import PostHog
import SwiftUI

struct ConnectFourGameView: View {
    @Environment(AppModel.self) private var appModel
    @State private var store: ConnectFourGameStore
    @State private var isNudging = false
    @State private var showingNudgeSent = false
    @State private var confettiTrigger = false
    @State private var celebratedSession: UUID?

    init(sessionID: UUID) {
        _store = State(initialValue: ConnectFourGameStore(sessionID: sessionID))
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
        .navigationTitle(GameType.connectFour.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.sessionID) { await store.load() }
        // Its own task: `subscribeRealtime()` loops until cancelled.
        .task(id: store.sessionID) { await store.subscribeRealtime() }
        // Only celebrates a win this player had. Confetti over a loss is the app congratulating
        // somebody for being beaten, and a draw is not a result to throw anything at either.
        .onChange(of: store.isFinished, initial: true) { _, finished in
            guard finished, store.didIWin == true, celebratedSession != store.sessionID else { return }
            celebratedSession = store.sessionID
            confettiTrigger.toggle()
        }
        .sensoryFeedback(.success, trigger: confettiTrigger)
        // A tap for every disc that lands, either player's. On a board you are both watching, the
        // partner's move arriving is the event worth feeling.
        .sensoryFeedback(.impact(weight: .light), trigger: store.moves.count)
        .onDisappear { store.stopRealtime() }
        .alert("Nudge sent", isPresented: $showingNudgeSent) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(appModel.partner.name) has been told it's their move.")
        }
        .postHogScreenView("Games: Connect 4")
    }

    private var content: some View {
        VStack(spacing: Theme.Spacing.md) {
            turnBanner

            ConnectFourBoardView(
                board: store.board,
                myDisc: store.myDisc,
                isInteractive: store.isMyTurn && !store.isPlaying,
                onDrop: { column in Task { await store.play(column: column) } }
            )
            .padding(.horizontal, Theme.Spacing.md)
            // Dimmed while it is not your move, so "you cannot play right now" is visible before a
            // tap is spent finding out.
            .opacity(store.isFinished || store.isMyTurn ? 1 : 0.75)

            if store.isFinished {
                resultCard
                    .padding(.horizontal, Theme.Spacing.md)
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
                    .fill(store.currentDisc == .first
                          ? ConnectFourBoardView.firstColor
                          : ConnectFourBoardView.secondColor)
                    .frame(width: 14, height: 14)
                Text(store.isMyTurn ? "Your move" : "\(appModel.partner.name)'s move")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
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
                    .foregroundStyle(store.isDraw ? Theme.subtleInk : Theme.leafGreen)

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
        if store.isDraw { return "equal.circle.fill" }
        return store.didIWin == true ? "trophy.fill" : "hands.clap.fill"
    }

    private var resultTitle: String {
        if store.isDraw { return "A draw" }
        // Named either way rather than only when it is good news. "You won" with nothing for the
        // other case leaves the loser's screen saying nothing at all about what just happened.
        return store.didIWin == true ? "You won" : "\(appModel.partner.name) won"
    }

    private var resultDetail: String {
        if store.isDraw {
            return "Forty-two discs and nowhere left to play. Start another from the games list."
        }
        return store.didIWin == true
            ? "Four in a row. Start another from the games list."
            : "They got four in a row. Start another from the games list."
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
}
