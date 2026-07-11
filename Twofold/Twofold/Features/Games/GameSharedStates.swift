//
//  GameSharedStates.swift
//  Twofold
//
//  Small pieces of UI shared by all four game views — the reveal-pending "waiting for
//  partner" state, the universal skip affordance, and the abandoned/error fallbacks.
//

import SwiftUI

/// The "you've answered, they haven't yet" state.
struct WaitingForPartnerView: View {
    let partnerName: String

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ProgressView()
            Text("Waiting for \(partnerName) to answer.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
    }
}

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
