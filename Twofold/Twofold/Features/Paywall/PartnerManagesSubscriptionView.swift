//
//  PartnerManagesSubscriptionView.swift
//  Twofold
//
//  Twofold subscriptions are shared per couple, but RevenueCat's `CustomerCenterView` only knows
//  about *this device's own* purchase history — for whichever partner didn't personally buy the
//  subscription, opening it showed a bare "no subscription" empty state, even though the couple
//  is actively covered by their partner's purchase. Shown instead, in any of the several places
//  that would otherwise route straight to `CustomerCenterView`, whenever the couple's active tier
//  isn't backed by this device's own local RevenueCat entitlement (see each call site's own
//  `subscriptionStore.subscribedTier == nil` check).
//

import SwiftUI

struct PartnerManagesSubscriptionView: View {
    var partnerName: String
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Theme.primaryButtonGradient)
                        .opacity(0.18)
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.skyBlue)
                }
                .frame(width: 96, height: 96)

                VStack(spacing: Theme.Spacing.sm) {
                    Text("\(partnerName) is managing your couple subscription")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    Text("Only they can cancel or change your plan, from their own Apple ID.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                Spacer()

                Button(action: onDismiss) {
                    Text("Got it")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.primaryButtonGradient, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: onDismiss)
                }
            }
        }
    }
}

#Preview {
    PartnerManagesSubscriptionView(partnerName: "Alex", onDismiss: {})
}
