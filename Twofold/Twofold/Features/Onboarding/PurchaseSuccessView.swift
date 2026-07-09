//
//  PurchaseSuccessView.swift
//  Twofold
//
//  Only reached after a real StoreKit purchase completes (see PaywallView's onSubscribed).
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
            progress: onboarding.progress,
            title: "Welcome to Twofold!",
            subtitle: "Your 14-day free trial has started.",
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

                    Text("We'll keep an eye on \(partnerName)'s journeys from here.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            },
            primaryTitle: "Continue",
            primaryAction: { appModel.finishOnboarding() }
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
