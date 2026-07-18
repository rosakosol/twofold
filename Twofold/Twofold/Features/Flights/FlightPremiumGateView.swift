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

                ZStack {
                    Circle()
                        .fill(Theme.primaryButtonGradient)
                        .opacity(0.18)
                    Image(systemName: icon)
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.skyBlue)
                    Circle()
                        .strokeBorder(Theme.subtleInk.opacity(0.15), lineWidth: 1)
                }
                .frame(width: 96, height: 96)
                .overlay(alignment: .bottomTrailing) {
                    ZStack {
                        Circle().fill(Theme.primaryButtonGradient)
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 30, height: 30)
                }

                VStack(spacing: Theme.Spacing.sm) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                Spacer()

                Button {
                    showingPaywall = true
                } label: {
                    Text("Continue to Premium")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .background(Theme.primaryButtonGradient, in: Capsule())
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
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
        title: "Delay Analysis",
        description: "This flight's 60-day on-time performance is part of Twofold Premium. Upgrade to see punctuality stats for every tracked flight."
    )
}
