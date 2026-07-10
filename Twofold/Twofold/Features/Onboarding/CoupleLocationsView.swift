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

    /// They live together, so there's only one city to ask for — it becomes both
    /// `homeCity` and `partnerCity` on continue.
    private var livesTogether: Bool { onboarding.situation == .liveTogetherTravelOften }

    var body: some View {
        OnboardingScaffold(
            title: "Where in the world are you two? 🌍",
            centered: true,
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    if livesTogether {
                        CityMenuPicker(label: "City", selection: $myCity)
                    } else {
                        CityMenuPicker(label: "Your city", selection: $myCity)
                        CityMenuPicker(label: "\(partnerName)'s city", selection: $partnerCity)
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: {
                onboarding.homeCity = myCity
                onboarding.partnerCity = livesTogether ? myCity : partnerCity
                onboarding.path.append(.anniversaryDate)
            },
            primaryDisabled: myCity == nil || (!livesTogether && partnerCity == nil)
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
