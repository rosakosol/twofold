//
//  PurchaseSuccessView.swift
//  Twofold
//
//  Reached after a real StoreKit purchase completes, or a restore finds one (see PaywallView's
//  onSubscribed).
//

import SwiftUI

struct PurchaseSuccessView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel
    @State private var didCelebrate = false
    @State private var heartScale: CGFloat = 0.6

    // PartnerNameView requires a non-empty name before you can advance, so by the time any
    // later onboarding screen runs, this is always the real name — no fallback needed.
    private var partnerName: String { onboarding.partnerName }

    var body: some View {
        OnboardingScaffold(
            title: "You're all set",
            // From what the paywall reports, not a constant. This used to say "Your 14-day free
            // trial has started." to everyone, including a restore and an account that was not
            // eligible for a trial and had just been charged.
            subtitle: (onboarding.subscriptionOutcome ?? .purchased(freeTrial: nil)).successSubtitle,
            content: {
                VStack(spacing: Theme.Spacing.lg) {
                    Text("❤️")
                        .font(.system(size: 80))
                        .scaleEffect(heartScale)
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                                heartScale = 1.0
                            }
                            didCelebrate = true
                        }

                    Text("We'll help you and your partner stay connected, wherever you are.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            },
            primaryTitle: "Continue",
            primaryAction: { Task { await appModel.finishOnboarding() } }
        )
        .sensoryFeedback(.success, trigger: didCelebrate)
    }
}

#Preview {
    NavigationStack {
        PurchaseSuccessView()
    }
    .environment(OnboardingModel())
    .environment(AppModel())
}
