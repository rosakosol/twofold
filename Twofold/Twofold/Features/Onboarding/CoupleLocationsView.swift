//
//  CoupleLocationsView.swift
//  Twofold
//

import SwiftUI

struct CoupleLocationsView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var myCity: Place?
    @State private var partnerCity: Place?
    @State private var locationService = HomeLocationService()

    // PartnerNameView requires a non-empty name before you can advance, so by the time any
    // later onboarding screen runs, this is always the real name — no fallback needed.
    private var partnerName: String { onboarding.partnerName }

    /// They live together, so there's only one city to ask for — it becomes both
    /// `homeCity` and `partnerCity` on continue.
    private var livesTogether: Bool { onboarding.situation == .liveTogetherTravelOften }

    var body: some View {
        OnboardingScaffold(
            title: "Where are you two based? 🌍",
            centered: true,
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        // "My city" is location-derived first, search picker only as a fallback
                        // — the picker stays visible throughout (not swapped out once resolved)
                        // so a wrong auto-detected city is still just as easy to correct by hand.
                        CityMenuPicker(label: livesTogether ? "City" : "Your city", selection: $myCity)

                        if locationService.state == .requesting {
                            HStack(spacing: Theme.Spacing.xs) {
                                ProgressView()
                                Text("Finding your city…").foregroundStyle(Theme.subtleInk)
                            }
                            .font(.caption)
                        } else if case .deniedOrRestricted = locationService.state {
                            Text("Location access is off — you can still search for your city above.")
                                .font(.caption2)
                                .foregroundStyle(Theme.subtleInk)
                        } else if case .failed = locationService.state {
                            Button {
                                locationService.requestCurrentLocation()
                            } label: {
                                Label("Try again", systemImage: "location.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.skyBlue)
                            }
                        }
                    }

                    if !livesTogether {
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
            if myCity == nil {
                locationService.requestCurrentLocation()
            }
        }
        .onChange(of: locationService.state) { _, newState in
            if case .resolved(let place) = newState {
                myCity = place
            }
        }
    }
}

#Preview {
    NavigationStack {
        CoupleLocationsView()
    }
    .environment(OnboardingModel())
}
