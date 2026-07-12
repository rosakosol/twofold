//
//  GameIntroView.swift
//  Twofold
//
//  Shown before a game starts (or before resuming one the partner already finished) — sets
//  expectations that this is asynchronous: answer now, partner joins whenever, results stay
//  hidden until both are done.
//

import SwiftUI

struct GameIntroView: View {
    let gameType: GameType
    var totalRounds: Int = 5
    /// True when a session already exists and the *other* partner has already completed all
    /// their rounds — changes the copy from "here's how this works" to "they're waiting on you."
    var partnerAlreadyFinished: Bool = false
    var partnerName: String = "Your partner"
    var isStarting: Bool = false
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            ZStack {
                Circle().fill(LinearGradient(colors: gameType.iconGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: gameType.icon)
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
            .frame(width: 88, height: 88)

            VStack(spacing: Theme.Spacing.sm) {
                Text(gameType.displayName)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                HStack(spacing: Theme.Spacing.md) {
                    Label("\(totalRounds) questions", systemImage: "list.number")
                    Label(gameType.durationLabel, systemImage: "clock")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.subtleInk)
            }

            Text(partnerAlreadyFinished
                ? "❤️ \(partnerName) already finished. Your answers are hidden until you both complete the game. Ready?"
                : "You'll answer the questions first. Your partner can join whenever they're ready. Results stay hidden until you've both finished.")
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            Spacer()
            Spacer()

            Button(action: onStart) {
                HStack {
                    if isStarting {
                        ProgressView().tint(.white)
                    } else {
                        Text(partnerAlreadyFinished ? "Start" : "Start Game")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
            }
            .background(Theme.primaryButtonGradient, in: Capsule())
            .foregroundStyle(.white)
            .disabled(isStarting)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}

#Preview {
    GameIntroView(gameType: .travelTrivia, onStart: {})
}
