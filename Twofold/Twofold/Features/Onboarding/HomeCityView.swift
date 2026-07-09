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

    var body: some View {
        OnboardingScaffold(
            progress: onboarding.progress,
            title: "Where are you based?",
            subtitle: "We'll use this to show the distance between you two.",
            content: {
                VStack(spacing: Theme.Spacing.sm) {
                    CityMenuPicker(label: "Your city", selection: $selected)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.heartRed)
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
