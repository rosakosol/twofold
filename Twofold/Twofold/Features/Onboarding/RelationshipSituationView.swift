//
//  RelationshipSituationView.swift
//  Twofold
//

import SwiftUI

struct RelationshipSituationView: View {
    @Environment(OnboardingModel.self) private var onboarding

    var body: some View {
        OnboardingScaffold(
            progress: onboarding.progress,
            title: "Which sounds most like you two?",
            content: {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(RelationshipSituation.allCases) { situation in
                        OnboardingCard(
                            icon: situation.emoji,
                            title: situation.title,
                            subtitle: situation.subtitle,
                            isSelected: onboarding.situation == situation
                        ) {
                            onboarding.situation = situation
                            // "How often do you see each other?" doesn't make sense for a
                            // couple that hasn't met yet — skip straight past it.
                            onboarding.path.append(situation == .haventMetYet ? .attribution : .frequency)
                        }
                    }
                }
            }
        )
    }
}

#Preview {
    NavigationStack {
        RelationshipSituationView()
    }
    .environment(OnboardingModel())
}
