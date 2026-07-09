//
//  TrialTrustView.swift
//  Twofold
//

import SwiftUI

struct TrialTrustView: View {
    @Environment(OnboardingModel.self) private var onboarding

    private let points = [
        "No payment due today",
        "Full access for 14 days",
        "Cancel anytime",
    ]

    var body: some View {
        OnboardingScaffold(
            title: "We want you to try Twofold for free ❤️",
            content: {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        ForEach(points, id: \.self) { point in
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.leafGreen)
                                Text(point)
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                    Text("We'll remind you before your free trial ends.")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            },
            primaryTitle: "Continue for free",
            primaryAction: { onboarding.path.append(.paywall) }
        )
    }
}

#Preview {
    NavigationStack {
        TrialTrustView()
    }
    .environment(OnboardingModel())
}
