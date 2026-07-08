//
//  OnboardingCoordinatorView.swift
//  Twofold
//

import SwiftUI

struct OnboardingCoordinatorView: View {
    @State private var onboarding = OnboardingModel()

    var body: some View {
        NavigationStack(path: $onboarding.path) {
            WelcomeView()
                .navigationDestination(for: OnboardingStep.self) { step in
                    destination(for: step)
                }
        }
        .environment(onboarding)
        .onOpenURL { url in
            guard let code = InviteCode.code(from: url) else { return }
            onboarding.resetForNewInvite(code: code)
        }
    }

    @ViewBuilder
    private func destination(for step: OnboardingStep) -> some View {
        switch step {
        case .createAccount:
            CreateAccountView()
        case .homeCity:
            HomeCityView()
        case .relationshipContext:
            RelationshipContextView()
        case .seeingFrequency:
            SeeingFrequencyView()
        case .connectPartner:
            ConnectPartnerView()
        case .shareInvite:
            ShareInviteView(onboarding: onboarding)
        case .enterPartnerCode:
            EnterPartnerCodeView()
        case .joinInvite:
            JoinInviteView()
        case .connectedReveal:
            ConnectedRevealView()
        case .nextTrip:
            NextTripView()
        case .addTripDetails:
            AddTripDetailsView(
                mode: .onboarding,
                partnerName: onboarding.inviterName ?? "Partner",
                onSave: { trip in
                    onboarding.draftedTrip = trip
                    onboarding.path.append(.reveal)
                }
            )
        case .reveal:
            OnboardingRevealView()
        }
    }
}

#Preview {
    OnboardingCoordinatorView()
        .environment(AppModel())
}
