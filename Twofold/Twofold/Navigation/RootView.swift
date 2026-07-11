//
//  RootView.swift
//  Twofold
//

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var subscriptionStore = SubscriptionStore()
    @State private var pendingInviteCode: String?

    var body: some View {
        Group {
            if appModel.isLoadingSession {
                ZStack {
                    Theme.backgroundGradient.ignoresSafeArea()
                    ProgressView()
                }
            } else if appModel.hasCouple {
                if appModel.isSubscriptionActive {
                    MainTabView()
                } else {
                    NavigationStack {
                        PaywallView(isDismissable: false)
                    }
                }
            } else {
                OnboardingCoordinatorView()
            }
        }
        .task {
            await appModel.restoreSession()
            await checkSubscription()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await checkSubscription() }
            }
        }
        // Only meaningful once signed in — `OnboardingCoordinatorView` has its own `onOpenURL`
        // for the pre-account case (that branch isn't mounted here, so there's no double
        // handling). This is what makes an invite link work for anyone who already has an
        // account, paired or not — previously it was a silent no-op for them.
        .onOpenURL { url in
            guard appModel.hasCouple, let code = InviteCode.code(from: url) else { return }
            pendingInviteCode = code
        }
        .sheet(isPresented: Binding(get: { pendingInviteCode != nil }, set: { if !$0 { pendingInviteCode = nil } })) {
            RedeemPartnerCodeView(prefilledCode: pendingInviteCode)
        }
    }

    /// Writes this device's own local StoreKit entitlement, then re-reads the OR'd truth
    /// across both partners — see `BackendService.updateSubscriptionStatus`/
    /// `fetchSubscriptionActive`. No-ops before onboarding is done (`hasCouple == false`),
    /// since there's nothing to gate yet.
    private func checkSubscription() async {
        guard appModel.hasCouple else { return }
        await subscriptionStore.refreshEntitlementsOnly()
        try? await BackendService.updateSubscriptionStatus(active: subscriptionStore.isSubscribed)
        if let active = try? await BackendService.fetchSubscriptionActive() {
            appModel.isSubscriptionActive = active
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel())
}
