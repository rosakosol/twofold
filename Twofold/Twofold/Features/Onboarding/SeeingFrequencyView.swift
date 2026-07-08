//
//  SeeingFrequencyView.swift
//  Twofold
//

import SwiftUI

struct SeeingFrequencyView: View {
    @Environment(OnboardingModel.self) private var onboarding

    var body: some View {
        OnboardingScaffold(
            title: "How often do you usually see each other?",
            content: {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(SeeingFrequency.allCases) { frequency in
                        OnboardingOptionRow(title: frequency.rawValue, isSelected: onboarding.seeingFrequency == frequency) {
                            onboarding.seeingFrequency = frequency
                            onboarding.path.append(.connectPartner)
                        }
                    }
                }
            },
            secondaryTitle: "Skip",
            secondaryAction: { onboarding.path.append(.connectPartner) }
        )
    }
}

#Preview {
    NavigationStack {
        SeeingFrequencyView()
    }
    .environment(OnboardingModel())
}
