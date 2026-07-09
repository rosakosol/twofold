//
//  CoupleLocationsView.swift
//  Twofold
//

import SwiftUI

struct CoupleLocationsView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var myCity: Place?
    @State private var partnerCity: Place?

    // PartnerNameView requires a non-empty name before you can advance, so by the time any
    // later onboarding screen runs, this is always the real name — no fallback needed.
    private var partnerName: String { onboarding.partnerName }

    var body: some View {
        OnboardingScaffold(
            title: "Where in the world are you two? 🌍",
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    CityMenuPicker(label: "Your city", selection: $myCity)
                    CityMenuPicker(label: "\(partnerName)'s city", selection: $partnerCity)
                }
            },
            primaryTitle: "Continue",
            primaryAction: {
                onboarding.homeCity = myCity
                onboarding.partnerCity = partnerCity
                onboarding.path.append(.personalizedInsight)
            },
            primaryDisabled: myCity == nil || partnerCity == nil
        )
        .onAppear {
            myCity = onboarding.homeCity
            partnerCity = onboarding.partnerCity
        }
    }
}

#Preview {
    NavigationStack {
        CoupleLocationsView()
    }
    .environment(OnboardingModel())
}
