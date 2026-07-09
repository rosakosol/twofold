//
//  OnboardingCoordinatorView.swift
//  Twofold
//

import SwiftUI
import GoogleSignIn

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
            // Google's sign-in flow redirects back into the app via its own URL scheme.
            if GIDSignIn.sharedInstance.handle(url) { return }
            guard let code = InviteCode.code(from: url) else { return }
            onboarding.resetForNewInvite(code: code)
        }
    }

    @ViewBuilder
    private func destination(for step: OnboardingStep) -> some View {
        switch step {
        case .situation:
            RelationshipSituationView()
        case .frequency:
            FrequencyView()
        case .attribution:
            AttributionView()
        case .goals:
            GoalsView()
        case .yourName:
            YourNameView()
        case .partnerName:
            PartnerNameView()
        case .gender:
            GenderView()
        case .benchmark:
            BenchmarkView()
        case .coupleLocations:
            CoupleLocationsView()
        case .personalizedInsight:
            PersonalizedInsightView()
        case .notificationsSell:
            NotificationsSellView()
        case .liveActivitySell:
            LiveActivitySellView()
        case .widgetSell:
            WidgetSellView()
        case .addFirstFlight:
            AddFirstFlightView()
        case .twofoldPreview:
            TwofoldPreviewView()
        case .trialTrust:
            TrialTrustView()
        case .paywall:
            PaywallView(onSubscribed: { onboarding.path.append(.purchaseSuccess) })
        case .purchaseSuccess:
            PurchaseSuccessView()
        case .saveAccount:
            SaveAccountView()
        case .createAccount:
            CreateAccountView()
        case .homeCity:
            HomeCityView()
        case .addPhoto:
            AddPhotoView()
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
