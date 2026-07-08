//
//  RelationshipContextView.swift
//  Twofold
//

import SwiftUI

struct RelationshipContextView: View {
    @Environment(OnboardingModel.self) private var onboarding

    var body: some View {
        OnboardingScaffold(
            title: "Are you currently in a long-distance relationship?",
            content: {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(RelationshipStatus.allCases) { status in
                        OnboardingOptionRow(title: status.rawValue, isSelected: onboarding.relationshipStatus == status) {
                            onboarding.relationshipStatus = status
                            onboarding.path.append(.seeingFrequency)
                        }
                    }
                }
            }
        )
    }
}

#Preview {
    NavigationStack {
        RelationshipContextView()
    }
    .environment(OnboardingModel())
}
