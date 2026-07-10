//
//  TrialTrustView.swift
//  Twofold
//

import SwiftUI

struct TrialTrustView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var shownPoints: Set<Int> = []
    @State private var iconPulsing = false

    private let points = [
        "No payment due today",
        "Full access for 14 days",
        "Cancel anytime",
    ]

    var body: some View {
        OnboardingScaffold(
            title: "We want you to try Twofold for free",
            content: {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    // Same pulsing GlobeHeart mark as the welcome screen, bookending onboarding.
                    Image("GlobeHeart")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .scaleEffect(iconPulsing ? 1.08 : 1.0)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.lg)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                                iconPulsing = true
                            }
                        }

                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.leafGreen)
                                Text(point)
                                    .font(.subheadline.weight(.medium))
                            }
                            .opacity(shownPoints.contains(index) ? 1 : 0)
                            .offset(x: shownPoints.contains(index) ? 0 : -16)
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .onAppear {
                        for index in points.indices {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.15 + Double(index) * 0.15)) {
                                _ = shownPoints.insert(index)
                            }
                        }
                    }

                    Text("We'll remind you before your free trial ends.")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            },
            primaryTitle: "Continue for free",
            // `.paywall`, not `.saveAccount` — the account screen already happened earlier in
            // the flow (after the widget sell), so going there again looped users back to sign-in.
            primaryAction: { onboarding.path.append(.paywall) }
        )
    }
}

#Preview {
    NavigationStack {
        TrialTrustView()
    }
    .environment({
        let model = OnboardingModel()
        model.firstName = "You"
        model.partnerName = "Erin"
        model.homeCity = Place.commonCities.first { $0.city == "Melbourne" }
        model.partnerCity = Place.commonCities.first { $0.city == "London" }
        return model
    }())
}
