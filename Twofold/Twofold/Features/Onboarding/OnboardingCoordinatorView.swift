//
//  OnboardingCoordinatorView.swift
//  Twofold
//

import SwiftUI
import GoogleSignIn
import PostHog

struct OnboardingCoordinatorView: View {
    @State private var onboarding = OnboardingModel()

    var body: some View {
        NavigationStack(path: $onboarding.path) {
            WelcomeView()
                .postHogScreenView("Onboarding: Welcome")
                .navigationDestination(for: OnboardingStep.self) { step in
                    destination(for: step)
                        .postHogScreenView(step.analyticsName)
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
        case .coupleLocations:
            CoupleLocationsView()
        case .anniversaryDate:
            AnniversaryDateView()
        case .personalizedInsight:
            PersonalizedInsightView()
        case .notificationsSell:
            NotificationsSellView()
        case .liveActivitySell:
            LiveActivitySellView()
        case .memoriesSell:
            MemoriesSellView()
        case .mapSell:
            MapSellView()
        case .widgetSell:
            WidgetSellView()
        case .invitePartner:
            InvitePartnerView()
        case .addFirstFlight:
            AddFirstFlightView()
        case .firstMemory:
            FirstMemoryView()
        case .twofoldPreview:
            TwofoldPreviewView()
        case .trialTrust:
            TrialTrustView()
        case .paywall:
            // isDismissable: false — this is pushed onto the onboarding path, not sheeted, so
            // there's nothing to dismiss to. Without this, `PaywallView.handleEntitlementChange`
            // would call `dismiss()` right after `onSubscribed()` appends `.purchaseSuccess`,
            // popping both it and this screen off `onboarding.path` in the same run-loop turn —
            // the white screen bug this comment is here to prevent regressing.
            PaywallView(onSubscribed: { onboarding.path.append(.purchaseSuccess) }, isDismissable: false)
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
