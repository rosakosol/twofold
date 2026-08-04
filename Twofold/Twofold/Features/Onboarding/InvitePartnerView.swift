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
//  Redeeming a partner's code here only ever creates a pending request now (see
//  RedeemPartnerCodeView, which already shows "request sent" before onRedeemSuccess fires) — the
//  inviter still has to accept it before a real couple exists, so this can't jump straight into
//  MainTabView the way it used to. Onboarding just continues normally; `RootView`'s own
//  background refresh picks up the couple once accepted, same as any other post-onboarding
//  connection.
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
                    inviteCode: $onboarding.inviteCode,
                    onRedeemSuccess: {
                        Task {
                            await appModel.applyOnboardingAccount(onboarding)
                            if appModel.hasCouple {
                                // Rare case a couple already existed by the time we get here
                                // (e.g. it was somehow already accepted) — nothing left to do.
                                return
                            }
                            // Redeeming only ever creates a *pending* request now (the inviter
                            // still has to accept it) — this used to continue straight to
                            // `.trialTrust`/the paywall regardless, which meant paying for a
                            // subscription before even knowing whether the other side will
                            // accept. `.reveal` is the same "you're all set, we'll let you know
                            // the moment you're connected" screen the manual-invite path already
                            // uses for exactly this pending state, and skips the paywall
                            // entirely — a couple only needs one subscription between them
                            // anyway, decided once someone's actually confirmed connected.
                            onboarding.path.append(.reveal)
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
