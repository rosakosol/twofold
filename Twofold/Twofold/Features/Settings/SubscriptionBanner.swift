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

    // This used to take a `coverageNote` naming which partner's subscription covered the couple.
    // It is gone, and the reason is worth keeping: nothing the app holds at first render can
    // answer that question. `appModel.isSubscriptionActive` says the couple is covered;
    // `RedundantSubscription` says whether *both* are; neither says who pays. Only RevenueCat's
    // own entitlement does, and that is a network round trip on a `SubscriptionStore` this screen
    // builds fresh every time it appears.
    //
    // So the line could only ever arrive late, and gating it on the loads finishing just moved the
    // change rather than removing it. A subtitle under a heading is the wrong place for a fact
    // that cannot be known yet — it is read in the first half-second or not at all. The
    // partner-covered case is explained properly by `PartnerManagesSubscriptionView`, which this
    // banner already opens for exactly those people and has room to say it in.

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
