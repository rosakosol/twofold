//
//  HomeCityView.swift
//  Twofold
//

import SwiftUI

struct HomeCityView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var selected: Place?

    var body: some View {
        OnboardingScaffold(
            title: "Where are you based?",
            subtitle: "We'll use this to show the distance between you two.",
            content: {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(Place.commonCities) { place in
                        OnboardingOptionRow(title: "\(place.city), \(place.country)", isSelected: selected?.id == place.id) {
                            selected = place
                        }
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: { advance() },
            primaryDisabled: false,
            secondaryTitle: "Skip for now",
            secondaryAction: { advance() }
        )
    }

    private func advance() {
        onboarding.homeCity = selected
        if onboarding.role == .inviter {
            onboarding.path.append(.relationshipContext)
        } else {
            onboarding.path.append(.connectedReveal)
        }
    }
}

#Preview {
    NavigationStack {
        HomeCityView()
    }
    .environment(OnboardingModel())
}
