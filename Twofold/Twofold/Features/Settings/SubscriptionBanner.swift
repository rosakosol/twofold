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
    /// Who the couple's one subscription belongs to, shown in place of the generic subtitle.
    ///
    /// Lives here rather than in a card of its own beneath: it is a sentence about the thing this
    /// banner already represents, and a separate card restated the same fact a second time with
    /// more ceremony than it needs.
    ///
    /// Nil while that is still unknown — before entitlements have resolved, or for someone with no
    /// partner to share with — and the generic subtitle stands in. Deliberately not defaulted to
    /// either partner: guessing gets it wrong half the time, and gets it wrong about money.
    var coverageNote: String? = nil
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
                    Text(coverageNote ?? (isSubscribed ? "View or change your plan" : "Games, widgets, and more for you both"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(Theme.Spacing.md)
            .background(Theme.primaryButtonGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .contentShape(Rectangle())
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
