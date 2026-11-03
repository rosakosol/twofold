//
//  FlightPremiumGateView.swift
//  Twofold
//
//  Same shape as `DeckPremiumGateView` (icon + crown badge, upsell copy, "Continue to Premium"
//  hand-off to the paywall) but generalized for Flight Details screen sections that are
//  Premium-only without being backed by a `GameDeck` row — delay analysis, good to know, flight
//  information. One reusable view parameterized by icon/title/description rather than three
//  near-identical ones.
//

import SwiftUI
import PostHog

struct FlightPremiumGateView: View {
    let icon: String
    let title: String
    let description: String

    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                GateHero(systemImage: icon, badge: .premium)

                VStack(spacing: Theme.Spacing.sm) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                Spacer()

                Button {
                    showingPaywall = true
                } label: {
                    Text("Continue to Premium")
                }
                .buttonStyle(.twofoldPrimary)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(ScreenBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .close) { dismiss() }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                NavigationStack { PaywallView(initialTier: .premium) }
                    .postHogScreenView("Paywall: Flight Premium Gate")
            }
        }
        .postHogScreenView("Flights: Premium Gate")
    }
}

#Preview {
    FlightPremiumGateView(
        icon: "chart.bar.fill",
        title: "Delay analysis",
        description: "This flight's 60-day on-time performance is part of Twofold Premium. Upgrade to see punctuality stats for every tracked flight."
    )
}
