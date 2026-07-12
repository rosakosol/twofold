//
//  SubscriptionBanner.swift
//  Twofold
//
//  Prominent Settings CTA — deliberately not just another SettingsRow, since subscription
//  status is the single highest-leverage thing to surface on this screen. No existing banner
//  component to reuse, so this introduces the pattern fresh: a gradient card rather than a
//  plain row, matching Theme.primaryButtonGradient used elsewhere for primary actions.
//

import SwiftUI

struct SubscriptionBanner: View {
    var isSubscribed: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image("GlobeHeart")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isSubscribed ? "Manage subscription" : "Unlock Twofold Plus")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(isSubscribed ? "View or change your plan" : "Games, widgets, and more for you both")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(Theme.Spacing.md)
            .background(Theme.primaryButtonGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        SubscriptionBanner(isSubscribed: false) {}
        SubscriptionBanner(isSubscribed: true) {}
    }
    .padding()
}
