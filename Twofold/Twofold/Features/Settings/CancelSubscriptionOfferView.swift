//
//  CancelSubscriptionOfferView.swift
//  Twofold
//
//  Shown right after a *paying* user successfully disconnects their partner (see
//  `DisconnectPartnerView`'s `isPayer` check) — their ex-partner's access is already gone the
//  moment the couple dissolves, regardless of what happens here; this is purely about whether
//  this device's own now-solo subscription keeps billing. `CustomerCenterView` (RevenueCat's
//  real, Apple-hosted cancel/manage flow) is a separate completable-or-abandonable step, not
//  something that can be sequenced inside the destructive disconnect confirmation itself — so it
//  lives here as its own optional offer instead.
//

import SwiftUI

struct CancelSubscriptionOfferView: View {
    var onManage: () -> Void
    var onNotNow: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Theme.primaryButtonGradient)
                        .opacity(0.18)
                    Image(systemName: "creditcard.trianglebadge.exclamationmark")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.skyBlue)
                }
                .frame(width: 96, height: 96)

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Keep your subscription?")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    Text("You're still subscribed — it's just yours alone now. If you'd rather not keep paying for it, you can cancel anytime, but you'll need an active plan again to keep using Twofold once it ends.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                Spacer()

                VStack(spacing: Theme.Spacing.sm) {
                    Button(action: onManage) {
                        Text("Manage Subscription")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.primaryButtonGradient, in: Capsule())
                            .foregroundStyle(.white)
                    }

                    Button("Keep My Subscription", action: onNotNow)
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: onNotNow)
                }
            }
        }
    }
}

#Preview {
    CancelSubscriptionOfferView(onManage: {}, onNotNow: {})
}
