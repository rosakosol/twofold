//
//  OfflineGameBanner.swift
//  Twofold
//
//  Shown whenever a session has answers sitting in GameSessionStore's offline queue — either
//  because we're offline right now, or a reconnect-triggered `syncPendingResponses()` just hasn't
//  finished yet. Purely informational; play continues underneath it either way.
//

import SwiftUI

struct OfflineGameBanner: View {
    let isConnected: Bool
    let pendingCount: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: isConnected ? "arrow.triangle.2.circlepath" : "wifi.slash")
                .foregroundStyle(Theme.subtleInk)
            Text(isConnected
                ? "Sending \(pendingCount) saved answer\(pendingCount == 1 ? "" : "s")…"
                : "You're offline — your answers are saved and will send once you're back online.")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
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
