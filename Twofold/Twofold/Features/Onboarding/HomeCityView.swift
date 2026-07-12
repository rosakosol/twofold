//
//  HomeCityView.swift
//  Twofold
//

import SwiftUI

struct HomeCityView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel
    @State private var selected: Place?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var locationService = HomeLocationService()

    var body: some View {
        OnboardingScaffold(
            title: "Where are you based?",
            subtitle: "We'll use this to show the distance between you two.",
            content: {
                VStack(spacing: Theme.Spacing.sm) {
                    CityMenuPicker(label: "Your city", selection: $selected)

                    Button {
                        locationService.requestCurrentLocation()
                    } label: {
                        HStack {
                            if locationService.state == .requesting {
                                ProgressView()
                                Text("Finding your city…").foregroundStyle(Theme.subtleInk)
                            } else {
                                Label("Use my current location", systemImage: "location.fill")
                                    .foregroundStyle(Theme.skyBlue)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(locationService.state == .requesting)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.heartRed)
                    }
                    if case .deniedOrRestricted = locationService.state {
                        Text("Location access is off — you can still search for your city above.")
                            .font(.caption2)
                            .foregroundStyle(Theme.subtleInk)
                    }
                }
                .onChange(of: locationService.state) { _, newState in
                    if case .resolved(let place) = newState {
                        selected = place
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: { advance() },
            primaryDisabled: isSaving,
            secondaryTitle: "Skip for now",
            secondaryAction: { advance() }
        )
    }

    private func advance() {
        onboarding.homeCity = selected
        isSaving = true
        errorMessage = nil
        Task {
            do {
                if let selected {
                    try await BackendService.updateHomeCity(selected)
                    appModel.couple.partnerA.homeCity = selected
                }
                if onboarding.role == .invitee {
                    try await BackendService.redeemInviteCode(onboarding.inviteCode ?? "")
                    onboarding.isPartnerConnected = true
                }
                onboarding.path.append(.addPhoto)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

#Preview {
    NavigationStack {
        HomeCityView()
    }
    .environment(OnboardingModel())
    .environment(AppModel())
}
