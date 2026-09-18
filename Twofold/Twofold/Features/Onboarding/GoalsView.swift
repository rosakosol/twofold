//
//  GoalsView.swift
//  Twofold
//

import SwiftUI

struct GoalsView: View {
    @Environment(OnboardingModel.self) private var onboarding

    var body: some View {
        OnboardingScaffold(
            title: "What would make time apart feel easier?",
            // Smaller than the scaffold's default `lg`, for the same reason the card spacing is
            // tightened below: this screen has five options to show and no room to spare.
            titleTopPadding: Theme.Spacing.sm,
            // No "Select all that apply". The cards carry circles rather than radio buttons and
            // stay selected as you tap more of them, which says it more clearly than a line of
            // instructions — and that line cost a row on a screen that had none to spare.
            content: {
                // `xs`, not the usual `sm`. Five cards plus a two-line heading and the pinned
                // Continue bar come to within a few points of the smallest supported screen, and
                // the gap between cards is the cheapest place to find them — the cards already
                // read as separate, each having its own surface and border.
                VStack(spacing: Theme.Spacing.xs) {
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
