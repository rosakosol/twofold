//
//  GoalsView.swift
//  Twofold
//

import SwiftUI

struct GoalsView: View {
    @Environment(OnboardingModel.self) private var onboarding

    var body: some View {
        OnboardingScaffold(
            progress: onboarding.progress,
            title: "What would make time apart feel easier?",
            subtitle: "Select all that apply",
            content: {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(OnboardingGoal.allCases) { goal in
                        OnboardingCard(
                            icon: goal.icon,
                            title: goal.title,
                            subtitle: goal.subtitle,
                            isSelected: onboarding.goals.contains(goal)
                        ) {
                            if onboarding.goals.contains(goal) {
                                onboarding.goals.remove(goal)
                            } else {
                                onboarding.goals.insert(goal)
                            }
                        }
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: { onboarding.path.append(.yourName) },
            primaryDisabled: onboarding.goals.isEmpty
        )
    }
}

#Preview {
    NavigationStack {
        GoalsView()
    }
    .environment(OnboardingModel())
}
