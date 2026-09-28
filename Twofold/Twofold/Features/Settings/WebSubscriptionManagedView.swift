//
//  WebSubscriptionManagedView.swift
//  Twofold
//
//  Where somebody who subscribed on twofoldapp.com.au is sent when they tap "Manage subscription".
//
//  They used to be sent to `PartnerManagesSubscriptionView`, which told them their partner was
//  paying and only that partner could cancel — untrue, and untrue in the direction that leaves
//  somebody unable to stop a charge. The banner's middle branch reads "the row says covered, and
//  this device holds no entitlement of its own", and a web purchase satisfies both: the entitlement
//  lives on RevenueCat's customer for the website, not in this device's StoreKit receipts. So every
//  web subscriber matched the partner case exactly, including the ones with no partner at all.
//
//  `CustomerCenterView` is not an option for them either — it only knows this device's own purchase
//  history, which is the whole reason that branch exists. The website's own account portal is the
//  real thing: `cancel-my-subscription` ends a Stripe-billed subscription at period end, for the
//  person who asks, at the moment they ask.
//

import SwiftUI

struct WebSubscriptionManagedView: View {
    var onDismiss: () -> Void

    /// Session-protected (see site/middleware.ts), which is why the copy below says to sign in
    /// rather than promising the page will simply open.
    private let portal = URL(string: "https://www.twofoldapp.com.au/account")!

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Theme.primaryButtonGradient)
                        .opacity(0.18)
                    Image(systemName: "globe")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.skyBlueText)
                }
                .frame(width: 96, height: 96)

                VStack(spacing: Theme.Spacing.sm) {
                    Text("You subscribed on the web")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    // Says where, and says why it is not here. Without the second half this reads as
                    // an arbitrary redirect — the App Store has no record of this subscription, so
                    // there is nothing for iOS to show or change.
                    Text("This plan is billed through our website rather than the App Store, so it's managed there too. Sign in with the same account to change or cancel it.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                Spacer()

                VStack(spacing: Theme.Spacing.sm) {
                    Link(destination: portal) {
                        Text("Manage on the web")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.primaryButtonGradient, in: Capsule())
                            .foregroundStyle(.white)
                    }

                    Button("Not now", action: onDismiss)
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
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
    WebSubscriptionManagedView(onDismiss: {})
}
