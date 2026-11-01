//
//  OfflineGameBanner.swift
//  Twofold
//
//  Shown whenever a session has answers sitting in GameSessionStore's offline queue — either
//  because we're offline right now, or a reconnect-triggered `syncPendingResponses()` just hasn't
//  finished yet. Purely informational; play continues underneath it either way.
//
//  The puzzle games show it too, for their one result (`isResult`), while that result is waiting
//  to be sent — see `PuzzleResult`.
//

import SwiftUI

struct OfflineGameBanner: View {
    let isConnected: Bool
    let pendingCount: Int
    /// A puzzle's finished result rather than a deck's answers.
    var isResult = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: isConnected ? "arrow.triangle.2.circlepath" : "wifi.slash")
                .foregroundStyle(Theme.textSecondary)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity)
        .themedCardBackground(cornerRadius: Theme.Radius.card)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("game.pendingBanner")
    }

    private var message: String {
        switch (isResult, isConnected) {
        case (false, true): "Sending \(pendingCount) saved answer\(pendingCount == 1 ? "" : "s")…"
        case (false, false): "You're offline — your answers are saved and will send once you're back online."
        // Connected and still waiting means the last try failed some other way. It is retried on
        // the next reconnect, foreground or launch, so "sending" is true without promising when.
        case (true, true): "Your result is saved on this phone and hasn't reached the server yet. It will send on its own."
        case (true, false): "You're offline — your result is saved on this phone and will send once you're back online."
        }
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        OfflineGameBanner(isConnected: false, pendingCount: 3)
        OfflineGameBanner(isConnected: true, pendingCount: 1)
    }
    .padding(.vertical)
    .background(Theme.backgroundGradient)
}
