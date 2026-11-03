//
//  DeckPremiumGateView.swift
//  Twofold
//
//  Shown when a Plus member taps a Premium-tier deck — Plus members can now see every deck (no
//  longer filtered out entirely, see AppModel.decks(for:)), so this explains what's actually
//  gating this one and hands off to the Paywall rather than the deck just silently not opening.
//

import PostHog
import SwiftUI

struct DeckPremiumGateView: View {
    let deck: GameDeck

    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                GateHero(emoji: deck.emoji, fill: deck.gameType.chipTint, badge: .premium)

                VStack(spacing: Theme.Spacing.sm) {
                    Text(deck.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("This deck is part of Twofold Premium. Upgrade to unlock it, plus every other Premium deck across every topic.")
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
                    .postHogScreenView("Paywall: Premium Deck")
            }
        }
        .postHogScreenView("Games: Deck Premium Gate")
    }
}

#Preview {
    DeckPremiumGateView(deck: GameDeck(id: UUID(), topic: "Travel", gameType: .triviaBattle, title: "Airport Chaos", emoji: "🛫", tier: "premium", sortOrder: 0, questionCount: 10))
}
