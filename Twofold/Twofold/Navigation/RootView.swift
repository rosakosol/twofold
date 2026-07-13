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
    @State private var showingPartnerConnectedCelebration = false
    @State private var showingPaywallFromWidget = false
    @State private var gameDeepLink: SessionRoute?

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
                Task { await WidgetSnapshotWriter.refresh(appModel: appModel) }
            }
        }
        // Only meaningful once signed in — `OnboardingCoordinatorView` has its own `onOpenURL`
        // for the pre-account case (that branch isn't mounted here, so there's no double
        // handling). This is what makes an invite link work for anyone who already has an
        // account, paired or not — previously it was a silent no-op for them.
        .onOpenURL { url in
            guard appModel.hasCouple else { return }
            if WidgetDeepLink.isPaywallLink(url) {
                showingPaywallFromWidget = true
            } else if let code = InviteCode.code(from: url) {
                pendingInviteCode = code
            }
        }
        .sheet(isPresented: Binding(get: { pendingInviteCode != nil }, set: { if !$0 { pendingInviteCode = nil } })) {
            RedeemPartnerCodeView(prefilledCode: pendingInviteCode)
        }
        .sheet(isPresented: $showingPaywallFromWidget) {
            NavigationStack { PaywallView() }
        }
        // Tapping a delivered game-reminder/results-ready push notification lands here —
        // `PushNotificationDelegate` parses the payload and posts this rather than reaching into
        // AppModel directly (same reasoning as `.didRegisterForRemoteNotifications`).
        .onReceive(NotificationCenter.default.publisher(for: .didTapGameNotification)) { notification in
            guard appModel.hasCouple, let link = notification.object as? GameNotificationDeepLink else { return }
            gameDeepLink = SessionRoute(id: link.sessionID, gameType: link.gameType)
        }
        .fullScreenCover(item: $gameDeepLink) { route in
            NavigationStack { gameDestinationView(gameType: route.gameType, sessionID: route.id) }
        }
        // Fires for every post-onboarding path that can newly connect a partner — redeeming a
        // code via Settings/PartnerSetupView, or a background refresh discovering the partner
        // redeemed one while this device was away. Onboarding's own pairing moment has its own,
        // more modest ConnectedRevealView as part of that flow, so this only ever fires once
        // `hasCouple` is already true (MainTabView mounted).
        //
        // `partnerConnected` also flips false → true on every cold launch of an already-paired
        // couple (it starts `false` by default and only becomes `true` once `restoreSession()`
        // finishes loading), which looks identical to a genuine new-pairing transition — so a
        // per-couple persisted flag is the actual gate here, not just the transition itself.
        .onChange(of: appModel.partnerConnected) { wasConnected, isConnected in
            guard !wasConnected, isConnected else { return }
            let key = "partnerConnectedCelebrationShown_\(appModel.couple.id.uuidString)"
            guard !UserDefaults.standard.bool(forKey: key) else { return }
            UserDefaults.standard.set(true, forKey: key)
            showingPartnerConnectedCelebration = true
        }
        .fullScreenCover(isPresented: $showingPartnerConnectedCelebration) {
            PartnerConnectedView()
        }
        // Suppressed (not just delayed) while the partner-connected celebration is up — two
        // modal presentations competing from the same view hierarchy at once is asking for
        // trouble. The binding's `get` naturally re-evaluates once the celebration dismisses,
        // so a milestone queued during that window still surfaces right after, no extra
        // re-trigger needed.
        .sheet(item: reviewPromptBinding) { milestone in
            ReviewPromptView(milestone: milestone)
        }
    }

    private var reviewPromptBinding: Binding<ReviewMilestone?> {
        Binding(
            get: { showingPartnerConnectedCelebration ? nil : appModel.pendingReviewMilestone },
            set: { appModel.pendingReviewMilestone = $0 }
        )
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
