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
    @Environment(\.dismiss) private var dismiss
    @State private var isNudging = false
    @State private var showingNudgeSent = false
    @State private var confirmingEnd = false
    @State private var endFailed: String?
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
        // Its own back button, not the system one.
        //
        // A notification opens a game through `RootView`'s `fullScreenCover`, which wraps it in a
        // fresh `NavigationStack` — and at the root of a fresh stack there is nothing to pop, so
        // the system back button is simply absent. That left every one of these screens with no
        // way out at all: the only exit was force-quitting the app. `dismiss()` is right in both
        // contexts, popping when pushed and closing the cover when it is the root, which is what
        // the four deck games have always done.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                GameBackButton(action: { dismiss() })
            }
        }
        .toolbar {
            // Only while the game is live. Once it is over there is nothing to end, and the menu
            // would be offering to close something already closed.
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
            // Says both things it does: no winner, and the board goes. Either of them may end it —
            // it is one shared board — so the partner needs to know this was not a resignation
            // recorded against them.
            Text("This ends it for both of you, with no winner, and clears the board so you can start a new game. \(appModel.partner.name) will see that it ended.")
        }
        .alert("Couldn't end the game", isPresented: .constant(endFailed != nil)) {
            Button("OK") { endFailed = nil }
        } message: {
            Text(endFailed ?? "")
        }
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
        .alert("Reminder Sent", isPresented: $showingNudgeSent) {
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
                onDrop: { column in Task { await store.play(column: column) } },
                // Taken from the move list rather than from `lastMoveColumn`, which is only set by
                // this device's own `play` — so a partner's disc appeared without falling.
                lastDropColumn: store.moves.last.flatMap { Int($0.move) },
                moveCount: store.moves.count
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
                // Whose move, as a face rather than only a name. Two people who play each other
                // repeatedly read the avatar faster than the sentence beside it, and "Your move"
                // never carried a name to read in the first place.
                AvatarView(person: store.isMyTurn ? appModel.currentUser : appModel.partner, size: 26)
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
                    .foregroundStyle(store.isDraw || store.closedWithoutResult ? Theme.subtleInk : Theme.leafGreen)

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
        if store.isDraw { return "equal.circle.fill" }
        return store.didIWin == true ? "trophy.fill" : "hands.clap.fill"
    }

    private var resultTitle: String {
        // A board that was ended or expired is not a draw, and calling it one would credit both of
        // them with a game neither played out.
        if store.closedWithoutResult { return "This game ended" }
        if store.isDraw { return "A draw" }
        // Named either way rather than only when it is good news. "You won" with nothing for the
        // other case leaves the loser's screen saying nothing at all about what just happened.
        return store.didIWin == true ? "You won" : "\(appModel.partner.name) won"
    }

    private var resultDetail: String {
        if store.closedWithoutResult {
            // Deliberately does not say which of the two it was. The screen cannot tell an ended
            // game from an expired one — both are just a closed session — and guessing would
            // sometimes tell somebody their partner walked away when in fact a fortnight passed.
            return "It was ended or left too long, so there's no winner. Start a new one from the games list."
        }
        if store.isDraw {
            return "Forty-two discs and nowhere left to play. Start another from the games list."
        }
        return store.didIWin == true
            ? "Four in a row. Start another from the games list."
            : "They got four in a row. Start another from the games list."
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

    /// Already sits on the page rather than inside a card, which is where `GameReminderButton`
    /// needs to be — it is filled with `Theme.cardBackground` to read as raised.
    private var nudgeButton: some View {
        GameReminderButton(isSending: isNudging) {
            isNudging = true
            Task {
                await store.nudgePartner()
                isNudging = false
                showingNudgeSent = true
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }
}
