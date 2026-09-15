//
//  SubscriptionRequiredView.swift
//  Twofold
//
//  The step between tapping something gated and being asked to pay for it.
//
//  Going straight to the paywall answers a question nobody asked. Somebody who tapped "Add memory"
//  wanted to add a memory; a list of plans and prices does not tell them why that did not happen,
//  and the most natural reading of it — that the app is broken, or that they have been billed
//  wrongly — is the wrong one. This says what was blocked, in the words of the thing they tapped,
//  before offering the thing that unblocks it.
//
//  It also says what is *not* blocked, which the paywall has no reason to mention: everything
//  already saved stays readable, exportable and deletable. That is the whole shape of the model
//  since 20261028000000, and this screen is where most people will meet it.
//

import PostHog
import SwiftUI

/// What the person was trying to do when they were stopped.
///
/// An enum with a whole sentence per case rather than a `String` spliced into one. Interpolating
/// a `String` into `Text` puts the sentence beyond Xcode's string extractor — only a literal
/// written directly inside `Text` is ever written back to the catalogue — so a parameterised
/// headline would have stayed English in every language while the body text around it translated.
/// That is the same trap `LegalConsentCheckbox` documents, and this is the same way out of it.
enum GatedFeature {
    case memories
    case trips
    case flights
    case dailyQuestion
}

struct SubscriptionRequiredView: View {
    let feature: GatedFeature

    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)

            Image(systemName: "lock.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.skyBlueText)

            VStack(spacing: Theme.Spacing.sm) {
                title
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)

                Text("Everything you've already saved stays exactly where it is. You can read it, export it and delete it at any time — a subscription is what lets you add to it.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.sm) {
                Button { showingPaywall = true } label: {
                    Text("See plans")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .background(Theme.primaryButtonGradient, in: Capsule())
                .foregroundStyle(.white)

                Button("Not now") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .sheet(isPresented: $showingPaywall) {
            NavigationStack { PaywallView() }
        }
        .postHogScreenView("Subscription Required")
    }

    /// One literal per case, each a complete sentence — see `GatedFeature`.
    @ViewBuilder
    private var title: some View {
        switch feature {
        case .memories: Text("Adding memories needs an active subscription")
        case .trips: Text("Adding trips needs an active subscription")
        case .flights: Text("Tracking flights needs an active subscription")
        case .dailyQuestion: Text("Today's question needs an active subscription")
        }
    }
}

#Preview {
    SubscriptionRequiredView(feature: .memories)
}
