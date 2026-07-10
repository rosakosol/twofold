//
//  AttributionView.swift
//  Twofold
//

import SwiftUI

struct AttributionView: View {
    @Environment(OnboardingModel.self) private var onboarding

    var body: some View {
        OnboardingScaffold(
            title: "Where did you hear about us?",
            content: {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(AttributionSource.allCases) { source in
                        OnboardingOptionRow(title: source.rawValue, isSelected: onboarding.attribution == source) {
                            onboarding.attribution = source
                            onboarding.path.append(.goals)
                        }
                    }
                }
            }
        )
    }
}

#Preview {
    NavigationStack {
        AttributionView()
    }
    .environment(OnboardingModel())
}
