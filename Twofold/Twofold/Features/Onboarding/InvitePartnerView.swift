//
//  InvitePartnerView.swift
//  Twofold
//
//  Real invite flow — unlike the sell screens around it, this one actually talks to the
//  backend. Only reachable once SaveAccountView has run, since generating a real, redeemable
//  code requires a signed-in account. The actual share-code/redeem-code UI is `PartnerConnectCard`
//  — the same shared component `PartnerSetupView` (post-onboarding) and `PartnerRequiredGateView`
//  (the direct-to-connect sheet for locked cards elsewhere) use, so there's exactly one
//  implementation of "connect with your partner" in the app, not a separate onboarding-only one.
//
//  If the user redeems a partner's code here (rather than sending their own), a real couple
//  now exists — `applyOnboardingAccount` picks that up and flips `hasCouple`, which `RootView`
//  uses to jump straight into `MainTabView`, skipping the remaining onboarding screens. That's
//  correct: they've just joined an already-set-up couple, whose subscription already covers
//  them (Twofold subscriptions are shared), so there's nothing left for them to set up.
//

import SwiftUI

struct InvitePartnerView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var onboarding = onboarding

        OnboardingScaffold(
            title: "Connect with \(onboarding.partnerName) 💞",
            subtitle: "Send them your code, or enter theirs to connect right now.",
            content: {
                PartnerConnectCard(
                    firstName: onboarding.firstName,
                    inviteCode: $onboarding.inviteCode,
                    onRedeemSuccess: {
                        Task {
                            // Picks up the couple that redeeming just created — if found, this
                            // sets `appModel.hasCouple = true`, and `RootView` takes it from here.
                            await appModel.applyOnboardingAccount(onboarding)
                            if !appModel.hasCouple {
                                onboarding.path.append(.trialTrust)
                            }
                        }
                    }
                )
            },
            primaryTitle: nil,
            primaryAction: nil,
            secondaryTitle: "Not now",
            secondaryAction: { onboarding.path.append(.trialTrust) }
        )
    }
}

#Preview {
    NavigationStack {
        InvitePartnerView()
    }
    .environment({
        let model = OnboardingModel()
        model.partnerName = "Erin"
        model.firstName = "Rosa"
        return model
    }())
    .environment(AppModel())
}
