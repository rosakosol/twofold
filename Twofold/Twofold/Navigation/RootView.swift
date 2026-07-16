//
//  RootView.swift
//  Twofold
//

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var subscriptionStore = SubscriptionStore()
    /// Drives the foreground-triggered "where am I now" refresh that replaced the old one-time
    /// manual home-city picker — see `refreshCurrentCityIfNeeded()`.
    @State private var currentCityService = HomeLocationService()
    @State private var lastLocationCheckAt: Date?
    @State private var pendingInviteCode: String?
    @State private var showingPartnerConnectedCelebration = false
    @State private var showingPaywallFromWidget = false
    @State private var gameDeepLink: SessionRoute?
    /// Which MainTabView tab is showing — lives here rather than inside MainTabView so a widget
    /// deep link (twofold://home, twofold://memories, twofold://passport) can switch it.
    @State private var selectedTab: MainTab = .home
    /// Non-tab widget destinations (a specific flight/memory/the drawing pad) that need their
    /// own screen rather than just switching tabs.
    @State private var recordDeepLink: WidgetDeepLink.Destination?

    var body: some View {
        Group {
            if appModel.isLoadingSession {
                ZStack {
                    Theme.backgroundGradient.ignoresSafeArea()
                    ProgressView()
                }
            } else if appModel.hasCouple {
                if appModel.isSubscriptionActive {
                    MainTabView(selection: $selectedTab)
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
            refreshCurrentCityIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await checkSubscription() }
                Task { await WidgetSnapshotWriter.refresh(appModel: appModel) }
                refreshCurrentCityIfNeeded()
            }
        }
        .onChange(of: currentCityService.state) { _, newState in
            if case .resolved(let place) = newState {
                Task { await appModel.updateCurrentCityIfChanged(place) }
            }
        }
        // Only meaningful once signed in — `OnboardingCoordinatorView` has its own `onOpenURL`
        // for the pre-account case (that branch isn't mounted here, so there's no double
        // handling). This is what makes an invite link work for anyone who already has an
        // account, paired or not — previously it was a silent no-op for them.
        .onOpenURL { url in
            guard appModel.hasCouple else { return }
            if let code = InviteCode.code(from: url) {
                pendingInviteCode = code
                return
            }
            guard let destination = WidgetDeepLink.destination(for: url) else { return }
            switch destination {
            case .paywall:
                showingPaywallFromWidget = true
            case .flight, .memory, .drawingPad:
                if appModel.isSubscriptionActive {
                    recordDeepLink = destination
                }
            case .home:
                selectedTab = .home
            case .memories:
                selectedTab = .memories
            case .passport:
                selectedTab = .passport
            }
        }
        .sheet(isPresented: Binding(get: { pendingInviteCode != nil }, set: { if !$0 { pendingInviteCode = nil } })) {
            RedeemPartnerCodeView(prefilledCode: pendingInviteCode)
        }
        .sheet(isPresented: $showingPaywallFromWidget) {
            NavigationStack { PaywallView() }
        }
        .fullScreenCover(item: $recordDeepLink) { destination in
            NavigationStack { recordDeepLinkDestination(destination) }
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
        // server-persisted flag is the actual gate here, not just the transition itself (see
        // AppModel.partnerConnectedCelebrationShown — survives a reinstall, unlike UserDefaults).
        .onChange(of: appModel.partnerConnected) { wasConnected, isConnected in
            guard !wasConnected, isConnected else { return }
            guard !appModel.partnerConnectedCelebrationShown else { return }
            appModel.markPartnerConnectedCelebrationShown()
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

    /// Only ever called for the three cases actually assigned to `recordDeepLink`
    /// (.flight/.memory/.drawingPad) — the tab/paywall cases route elsewhere in `.onOpenURL`.
    @ViewBuilder
    private func recordDeepLinkDestination(_ destination: WidgetDeepLink.Destination) -> some View {
        switch destination {
        case .flight(let id):
            if let flight = appModel.flights.first(where: { $0.id == id }) {
                FlightTrackingView(flight: flight)
            } else {
                GameErrorState(message: "This flight isn't available anymore.")
            }
        case .memory(let id):
            if let memory = appModel.memories.first(where: { $0.id == id }) {
                MemoryDetailView(memory: memory)
            } else {
                GameErrorState(message: "This memory isn't available anymore.")
            }
        case .drawingPad:
            DrawingPadEditorView()
        case .paywall, .home, .memories, .passport:
            EmptyView()
        }
    }

    private var reviewPromptBinding: Binding<ReviewMilestone?> {
        Binding(
            get: { showingPartnerConnectedCelebration ? nil : appModel.pendingReviewMilestone },
            set: { appModel.pendingReviewMilestone = $0 }
        )
    }

    /// Writes this device's own RevenueCat entitlement state, then re-reads the OR'd truth
    /// across both partners — see `BackendService.updateSubscriptionStatus`/
    /// `fetchSubscriptionActive`. No-ops before onboarding is done (`hasCouple == false`),
    /// since there's nothing to gate yet.
    private func checkSubscription() async {
        guard appModel.hasCouple else { return }
        await subscriptionStore.refreshEntitlementsOnly()
        try? await BackendService.updateSubscriptionStatus(active: subscriptionStore.isSubscribed, tier: subscriptionStore.subscribedTier?.dbValue)
        if let active = try? await BackendService.fetchSubscriptionActive() {
            appModel.isSubscriptionActive = active
        }
    }

    /// Foreground-triggered re-derivation of the signed-in user's current city — replaces the
    /// old one-time manual "set my home city" flow. Throttled to roughly once an hour (a quick
    /// app switch shouldn't trigger a location fix + reverse-geocode every time); the actual
    /// write only happens if the resolved city differs from what's stored, see
    /// `AppModel.updateCurrentCityIfChanged(_:)`. Denied/restricted permission is a silent
    /// no-op — `HomeLocationService`'s own state machine already reflects that, no nagging here.
    private func refreshCurrentCityIfNeeded() {
        guard appModel.hasCouple else { return }
        if let lastLocationCheckAt, Date.now.timeIntervalSince(lastLocationCheckAt) < 3600 { return }
        lastLocationCheckAt = .now
        currentCityService.requestCurrentLocation()
    }
}

#Preview {
    RootView()
        .environment(AppModel())
}
