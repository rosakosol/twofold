//
//  GameSharedStates.swift
//  Twofold
//
//  Small pieces of UI shared by all four game views — the universal skip affordance and the
//  abandoned/error fallbacks. The mid-game "waiting for partner" state is gone — each partner
//  now walks straight through their own rounds independently; see GameCompletionView for the
//  new end-of-my-rounds waiting state instead.
//

import SwiftUI

/// Content-safety requirement: every prompt must be skippable.
struct SkipButton: View {
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button("Skip", action: action)
            .font(.subheadline)
            .foregroundStyle(Theme.subtleInk)
            .disabled(isDisabled)
    }
}

struct GameAbandonedState: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "flag.slash.fill").font(.largeTitle).foregroundStyle(Theme.subtleInk)
            Text("This game was left unfinished.")
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GameErrorState: View {
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(Theme.heartRed)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
