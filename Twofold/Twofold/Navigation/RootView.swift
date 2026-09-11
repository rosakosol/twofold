//
//  RootView.swift
//  Twofold
//

import PostHog
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var subscriptionStore = SubscriptionStore()
    @State private var appLock = AppLockService()
    /// Drives the foreground-triggered "where am I now" refresh that replaced the old one-time
    /// manual home-city picker — see `refreshCurrentCityIfNeeded()`.
    @State private var currentCityService = HomeLocationService()
    @State private var lastLocationCheckAt: Date?
    @State private var pendingInviteCode: String?
    @State private var showingPartnerConnectedCelebration = false
    @State private var showingPaywallFromWidget = false
    /// False until `checkSubscription()` has run once this launch.
    ///
    /// Nothing before it can answer "is this person subscribed". `restoreSession` applies the
    /// cached answer and then `loadSignedInState` overwrites it with the bare profile row — which
    /// is `false` for anyone whose webhook is behind, or whose entitlement RevenueCat still holds
    /// but Supabase has not caught up on. `checkSubscription` is the first thing to OR those two
    /// together, and it runs last. In the window between, the gate below would otherwise show a
    /// forced paywall to a paying subscriber and then take it away again a round trip later.
    @State private var hasCheckedSubscription = false
    /// A broken streak this person has already been offered a repair for, as the missed date.
    ///
    /// Keyed on the date rather than a bare flag so a *later* break offers again — the point is one
    /// showing per break, not one showing ever. Stored per device, which is per person in every
    /// case that matters: both partners get their own single showing, since it is their streak too
    /// and neither should hear about it only from the other. Someone with two devices sees it once
    /// on each, which is the cost of not putting a row in the database for a popup.
    @AppStorage("streakRepairOfferedForMissedDate") private var streakRepairOfferedFor = ""
    @State private var showingStreakRepair = false
    @State private var gameDeepLink: SessionRoute?
    /// Which MainTabView tab is showing — lives here rather than inside MainTabView so a widget
    /// deep link (twofold://home, twofold://memories, twofold://passport) can switch it.
    @State private var selectedTab: MainTab = .home
    /// Non-tab widget destinations (a specific flight/memory/the drawing pad) that need their
    /// own screen rather than just switching tabs.
    @State private var recordDeepLink: WidgetDeepLink.Destination?
    /// A Stats card a deep link asked for, consumed by `PassportView` once it appears. Without it
    /// the Days Together widget landed on whichever card happened to be open from last time.
    @State private var pendingStatsSection: StatsSection?
    /// The one-time "you're offline" explainer, and the flag that keeps it to once per launch —
    /// it's an orientation, not an alarm to re-raise every time the signal drops in a tunnel.
    @State private var showingOfflineNotice = false
    @State private var hasShownOfflineNotice = false
    /// Pending "you've gone offline" announcement, held so a brief blip can cancel it.
    @State private var offlineNoticeTask: Task<Void, Never>?
    private var network = NetworkMonitor.shared
    /// Where a tapped notification wants to go, held until this view can actually get there — see
    /// `consumePendingRoute()` and `NotificationRouter`.
    @State private var router = NotificationRouter.shared

    var body: some View {
        ZStack {
        Group {
            if appModel.isLoadingSession {
                loadingScreen
            } else if appModel.hasCouple {
                // Not really solo — redeemed a code and is waiting on the inviter's decision,
                // with no subscription of their own to be asked for (Twofold subscriptions are
                // shared; they'll inherit the couple's plan once accepted). The inviter always
                // subscribes before ever inviting anyone, so someone will always be covering
                // this — the forced paywall below would otherwise be a dead end for no reason.
                // Home shows a persistent "invite pending" card (with a reminder nudge) in place
                // of the old full-screen `PendingConnectionApprovalView` gate this used to be.
                // `subscriptionStore.isSubscribed` is in this condition because the profile row is
                // a cache, not the truth. It is written by `revenuecat-webhook`, and between a
                // purchase completing and that webhook landing — or while it is misconfigured, or
                // if RevenueCat never retried after a failure — the row says `false` for someone who
                // has genuinely paid.
                //
                // That gap was a dead end, not just a delay: the forced paywall below has nothing to
                // sell someone who already holds an entitlement, so it renders "Current Plan"
                // greyed out for their own tier and "Manage Subscription" for the other one, with no
                // way into the app at all. Reported by a real subscriber who could not get past it.
                //
                // Not a bypass. `customerInfo.entitlements.active` is RevenueCat's own answer,
                // receipt-validated against Apple server-side — the same source the webhook reads,
                // just not yet persisted. What it deliberately does not do is write that to the
                // profile row: that write is what let a client grant itself, and its partner,
                // Premium, and it stays the webhook's alone.
                if Self.hasAccess(
                    backendSaysActive: appModel.isSubscriptionActive,
                    deviceHoldsEntitlement: subscriptionStore.isSubscribed,
                    awaitingPartnerDecision: appModel.pendingOutgoingConnectionRequest != nil
                ) {
                    MainTabView(selection: $selectedTab, statsSection: $pendingStatsSection)
                } else if !hasCheckedSubscription {
                    // The same bargain as the branch below, for the subscription rather than the
                    // invite: a beat of loading costs a subscriber nothing, where a paywall that
                    // appears and is then retracted costs them their confidence that they are
                    // actually paid up. Someone genuinely lapsed reaches the paywall one round trip
                    // later, which is the right way round.
                    loadingScreen
                } else if !appModel.hasResolvedOutgoingConnectionRequest {
                    // Holds the loading screen rather than showing a paywall we might be about to
                    // retract. Whether this person is exempt depends on a request lookup that is
                    // still in flight — `restoreSession` flips `hasCouple` true and the body
                    // re-evaluates on the next await, several awaits before that lookup lands.
                    //
                    // The person this protects is the one who redeemed an invite and is waiting on
                    // the inviter: they are never meant to be asked to pay, and a paywall that
                    // appears and then vanishes is worse than a beat of loading — it is what makes
                    // someone reach for their card.
                    loadingScreen
                } else if let lapsedPartnerName = appModel.partnerSubscriptionLapsedPartnerName {
                    // The payer disconnected and this profile wasn't the one backing the
                    // couple's access — see `leave_couple`'s partner_subscription_lapse_*
                    // columns. Shown once instead of falling straight into the generic
                    // "resubscribe" paywall with no context for why access just disappeared.
                    NavigationStack {
                        SubscriptionLapsedFromDisconnectView(partnerName: lapsedPartnerName)
                    }
                    .postHogScreenView("Paywall: Subscription Lapsed From Disconnect")
                } else {
                    NavigationStack {
                        PaywallView(isDismissable: false)
                    }
                    .postHogScreenView("Paywall: Lapsed Subscription")
                }
            } else {
                OnboardingCoordinatorView()
            }
        }
        .task {
            KeyboardDismissal.installOnce()
            await appModel.restoreSession()
            // Before `checkSubscription`, not after: this is what decides whether the person is
            // exempt from the paywall at all, so resolving it first keeps the loading state above
            // to a single round trip instead of two.
            await refreshPendingOutgoingConnectionRequestIfNeeded()
            await checkSubscription()
            // Deliberately after both of the above: a notification tap that cold-launched the app
            // arrives long before either has finished, and `consumePendingRoute()` refuses to open
            // anything until they have.
            consumePendingRoute()
            refreshCurrentCityIfNeeded()
        }
        // Entitlement changes as RevenueCat learns of them, rather than only at the next
        // foreground. A plan change made in Settings › Apple Account › Subscriptions never tells
        // the app anything, so without this the tier stayed whatever the last foreground read
        // until another one happened to come along.
        .task {
            for await tier in subscriptionStore.entitlementUpdates() {
                guard appModel.hasCouple else { continue }
                // Read-only. This used to push the new entitlement to the profile row first; the
                // webhook does that now, and the client is refused if it tries (see
                // `BackendService`'s note where that write used to live). RevenueCat delivers the
                // same change to both, so the row is either already updated or about to be.
                if let coupleTier = try? await BackendService.fetchCoupleSubscriptionTier() {
                    appModel.subscriptionTier = coupleTier
                }
                if let active = try? await BackendService.fetchSubscriptionActive() {
                    appModel.isSubscriptionActive = active || tier != nil
                }
                await WidgetSnapshotWriter.refresh(appModel: appModel)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Sequential in one `Task`, not two separate concurrent ones — both
                // `checkSubscription()` and `refreshCoupleStateIfNeeded()` independently touch
                // Supabase's auth/session layer, and firing them at the same time on every single
                // foreground (compounded by `HomeView`'s own foreground refreshes doing the same,
                // see its doc comment) is what a live crash report traced a main-thread hang and
                // eventual watchdog kill back to — many concurrent callers all contending for the
                // SDK's internal auth-session lock at once. One after another still keeps both
                // fresh on every foreground, just without the pile-up.
                Task {
                    await checkSubscription()
                    // Previously only HomeView (inside MainTabView) ever re-checked couple state
                    // on foreground — meaning someone stuck on `PendingConnectionApprovalView`
                    // (below; never mounts MainTabView) had no way to discover their request
                    // being accepted short of force-quitting. This covers that, and is harmless/
                    // no-op otherwise.
                    await appModel.refreshCoupleStateIfNeeded()
                    // Appended to this same sequential Task rather than a concurrent one, for the
                    // auth-lock-contention reason above. Re-reported every foreground so the day
                    // boundary follows someone who travels — see `BackendService.updateTimezone`.
                    if appModel.hasCouple { try? await BackendService.updateTimezone() }
                }
                Task { await refreshPendingOutgoingConnectionRequestIfNeeded() }
                refreshCurrentCityIfNeeded()
            } else if newPhase == .background {
                // Only meaningful once signed in — locking behind Face ID/passcode while signed
                // out (mid-onboarding, or after a sign-out on a device that had this enabled from
                // a previous account) gated the sign-in/onboarding screens themselves behind a
                // biometric prompt for no reason, since there's nothing sensitive to protect yet.
                if appModel.hasCouple {
                    appLock.lock()
                }
            }
        }
        // Offline at launch: say so once, after giving the monitor a moment to deliver its first
        // real reading. `isConnected` defaults to `true` and `NWPathMonitor` reports asynchronously,
        // so asking immediately always answers "connected" — the same race that made the offline
        // launch path unreachable (see `AppModel.restoreSession`).
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !network.isConnected, appModel.hasCouple, !hasShownOfflineNotice else { return }
            hasShownOfflineNotice = true
            showingOfflineNotice = true
        }
        // Connectivity changing while the app is already open, in both directions. Neither used to
        // be handled: the notice fired once at launch and never again, so turning on airplane mode
        // mid-session left the app looking exactly as it had a moment earlier — right up until
        // something it needed silently failed.
        //
        // Everything that reads data already re-checks `NetworkMonitor` at call time and falls back
        // to its cache, and `isConnected` is observable so views following it re-render on their
        // own. What was missing is telling the person, and re-arming so a *later* drop is announced
        // too.
        .onChange(of: network.isConnected) { wasConnected, isConnected in
            guard wasConnected != isConnected else { return }

            offlineNoticeTask?.cancel()

            if !isConnected {
                // The only reason to wait at all is to coalesce the burst NWPathMonitor emits
                // mid-transition: it reports a Wi-Fi to cellular handover as unsatisfied and then
                // satisfied again in quick succession, and announcing that would be announcing
                // nothing.
                //
                // 250ms is near the floor of what is useful. Measured end to end at 400ms, the gap
                // from the drop to this firing was 429ms — so the scheduling overhead is about
                // 30ms and the rest is this number. Below roughly this, the burst stops being
                // coalesced; above it, the wait is dead time, because the sheet's own presentation
                // animation is longer than the delay either way. Shortening it further would not be
                // visible, and would cost false positives.
                //
                // Short delays are only safe at all because of the dismissal on the way back up: if
                // this does fire on a blip, the notice takes itself away rather than sitting there
                // claiming the app is offline while it is not.
                offlineNoticeTask = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, !network.isConnected,
                          appModel.hasCouple, !hasShownOfflineNotice else { return }
                    hasShownOfflineNotice = true
                    showingOfflineNotice = true
                }
                return
            }

            // Re-armed on the way back up, so a second trip through a tunnel is announced rather
            // than passing in silence — and the notice is taken away if it is still showing, since
            // it is now saying something untrue. This is what makes the short delay above safe: a
            // false positive corrects itself instead of needing to be dismissed by hand.
            hasShownOfflineNotice = false
            showingOfflineNotice = false

            guard appModel.hasCouple else { return }
            Task {
                await appModel.refreshCoupleStateIfNeeded()
                // Before `refreshAll`, which reloads the deck list: a deck played offline only
                // becomes a real session here, and until it does its progress isn't anywhere the
                // deck list could read it.
                if await LocalGameSessionSync.flush() {
                    await appModel.refreshGameDecks()
                }
                await appModel.refreshAll()
                await checkSubscription()
            }
        }
        .sheet(isPresented: $showingOfflineNotice) {
            OfflineNoticeView()
                // Full height, not `.medium`: this is a list of what does and doesn't work, and at
                // half a screen it showed one and a half rows of it.
                .presentationDetents([.large])
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
            case .flight, .memory, .trip, .drawingPad, .partnerDrawingPad:
                if appModel.isSubscriptionActive {
                    recordDeepLink = destination
                }
            case .home:
                selectedTab = .home
            case .memories:
                selectedTab = .memories
            case .passport(let section):
                pendingStatsSection = section
                selectedTab = .passport
            }
        }
        .sheet(isPresented: Binding(get: { pendingInviteCode != nil }, set: { if !$0 { pendingInviteCode = nil } })) {
            RedeemPartnerCodeView(prefilledCode: pendingInviteCode)
        }
        .sheet(isPresented: $showingPaywallFromWidget) {
            NavigationStack { PaywallView() }
                .postHogScreenView("Paywall: Widget")
        }
        // Watched rather than checked once on appear: the state arrives from a round trip that
        // lands well after this view first draws, and on a foreground it can change again.
        .onChange(of: appModel.streakRepair?.missedDateRaw) { _, _ in offerStreakRepairIfDue() }
        .sheet(isPresented: $showingStreakRepair) { streakRepairSheet }
        .fullScreenCover(item: $recordDeepLink) { destination in
            NavigationStack { recordDeepLinkDestination(destination) }
        }
        // A tapped notification can land here at any point — including before this view exists at
        // all, which is why `NotificationRouter` holds it rather than broadcasting it. Both
        // triggers matter: `onChange` covers a tap while the app is already up, and the `.task`
        // above calls `consumePendingRoute()` again once the session has finished restoring, which
        // covers a tap that launched the app cold and has been waiting ever since.
        .onChange(of: router.pending) { _, _ in consumePendingRoute() }
        // Watches the readiness condition itself rather than any one input to it. Observing only
        // `isSubscriptionActive` was subtly wrong and intermittently lost the route: session
        // restore finishes *before* `isLoadingSession` flips, so the `.task` call above runs while
        // still gated, and if the subscription flag never changed after that (it's often already
        // true from cache) nothing came back for the waiting route.
        .onChange(of: isReadyForNotificationRoute) { _, ready in
            if ready { consumePendingRoute() }
        }
        .fullScreenCover(item: $gameDeepLink) { route in
            // The typed game view's own back button (during active play or once results show)
            // now just calls `dismiss()` — from here, the root of a fresh `NavigationStack`
            // inside this `fullScreenCover`, that correctly closes the whole cover instead of
            // being a no-op. No separate Close button needed on top of that one.
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
                .postHogScreenView("Partner Connected Celebration")
        }
        // Suppressed (not just delayed) while the partner-connected celebration is up — two
        // modal presentations competing from the same view hierarchy at once is asking for
        // trouble. The binding's `get` naturally re-evaluates once the celebration dismisses,
        // so a milestone queued during that window still surfaces right after, no extra
        // re-trigger needed.
        .sheet(item: reviewPromptBinding) { milestone in
            ReviewPromptView(milestone: milestone)
                .postHogScreenView("Review Prompt")
        }
        // Same suppression reasoning as the review prompt above — never compete with the
        // partner-connected celebration or the review prompt for the same sheet slot.
        .sheet(isPresented: partnerInviteNudgeBinding) {
            PartnerInviteNudgeView()
                .postHogScreenView("Partner Invite Nudge")
        }

        // On top of everything above the loading spinner, but still gated on `hasCouple` — the
        // lock exists to protect an already-signed-in account's content, not to gate sign-in/
        // onboarding itself. `appLock.isLocked` starts pre-set from the persisted preference
        // before this view's first render regardless of sign-in state (see its own doc comment),
        // so without this check, a device that had the lock enabled from a previous account —
        // or that simply cold-launches straight into onboarding after a sign-out — would demand
        // Face ID/passcode just to reach the sign-in screen, with nothing sensitive to protect.
        if appModel.hasCouple && appLock.isEnabled && appLock.isLocked {
            AppLockView(appLock: appLock)
                .transition(.opacity)
                .zIndex(1)
        }
        }
    }

    /// Opens whatever a tapped notification pointed at, if this view is in a position to.
    ///
    /// The old handler dropped the link whenever `hasCouple`/`isSubscriptionActive` were false.
    /// Both start out false and only become true once `restoreSession()` and `checkSubscription()`
    /// have made their network round trips — which is precisely the state the app is in when a
    /// notification tap launched it. So the guard that was meant to stop an old notification
    /// bypassing the paywall was, in practice, throwing away almost every legitimate deep link.
    ///
    /// The gate is kept — an old notification sitting in Notification Center from before a lapse
    /// still must not become a way into premium gameplay — but not-ready now means *leave it
    /// pending* rather than discard. Whichever of the two triggers fires next tries again, and the
    /// route is only cleared once something has actually opened.
    /// Whether to show the app rather than the forced paywall.
    ///
    /// The one loading state, shared by every branch that is waiting to find out which screen
    /// this person should be on. Three copies of it had accumulated, one per thing that can still
    /// be in flight at launch, and they have to stay identical: a spinner that changes appearance
    /// depending on *why* it is waiting reads as the app flickering between screens.
    private var loadingScreen: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            BrandLoadingView()
        }
    }

    /// Kept as a named decision rather than an inline condition because the middle term is the one
    /// that is easy to drop and expensive to lose — see the comment at the call site. A forced
    /// paywall shown to someone who already holds an entitlement is a dead end, not a prompt: it has
    /// nothing to sell them, so it disables its own CTA and traps them.
    static func hasAccess(backendSaysActive: Bool, deviceHoldsEntitlement: Bool, awaitingPartnerDecision: Bool) -> Bool {
        backendSaysActive || deviceHoldsEntitlement || awaitingPartnerDecision
    }

    /// Everything that has to be true before a route can be opened. `isSubscriptionActive` is
    /// part of it deliberately: this presents over the whole app, including the non-dismissable
    /// lapsed-subscription paywall, so an old notification left sitting in Notification Center
    /// from before a lapse must not become a way back into premium gameplay.
    private var isReadyForNotificationRoute: Bool {
        !appModel.isLoadingSession && appModel.hasCouple && appModel.isSubscriptionActive
    }

    /// Shows the repair offer once for this break, then never again for it.
    ///
    /// The record is written when it is *shown*, not when it is acted on. Someone who closed the
    /// popup has answered it, and reopening the app should not ask a second time — which is the
    /// whole difference between an offer and a nag.
    private func offerStreakRepairIfDue() {
        guard let repair = appModel.streakRepair,
              repair.repairable,
              repair.streakAtRisk > 0,
              // No key means no way to tell one break from another, and an offer that cannot be
              // recorded is one that would return every launch. Better not shown at all.
              let missedDate = repair.missedDateRaw,
              missedDate != streakRepairOfferedFor
        else { return }

        streakRepairOfferedFor = missedDate
        showingStreakRepair = true
    }

    /// Pulled out of `body` purely to keep it type-checkable — that expression is already at the
    /// compiler's limit, and an inline `if let` inside the sheet tipped it over.
    @ViewBuilder
    private var streakRepairSheet: some View {
        if let streak = appModel.streakRepair?.streakAtRisk {
            StreakRepairPromptView(streak: streak)
        }
    }

    private func consumePendingRoute() {
        guard let route = router.pending, isReadyForNotificationRoute else { return }

        switch route {
        case .game(let sessionID, let gameType):
            gameDeepLink = SessionRoute(id: sessionID, gameType: gameType)
        case .dailyQuestion:
            // The push is scheduled before anyone has opened (and so created) the day's session,
            // so it carries no id. `DailyActivityCard`'s own `.task` resolves and opens it; landing
            // on the tab it sits at the top of is the reliable way in.
            selectedTab = .games
        case .flight(let id):
            recordDeepLink = .flight(id)
        case .drawingPad:
            recordDeepLink = .drawingPad
        case .partnerDrawingPad:
            recordDeepLink = .partnerDrawingPad
        case .invitePartner:
            selectedTab = .home
        }

        router.pending = nil
    }

    /// Only ever called for the four cases actually assigned to `recordDeepLink`
    /// (.flight/.memory/.drawingPad/.partnerDrawingPad) — the tab/paywall cases route elsewhere
    /// in `.onOpenURL`.
    ///
    /// `.flight`/`.memory` get an explicit Close button here; the two drawing-pad cases don't
    /// need one, since `DrawingPadEditorView` and `DrawingPadFullScreenView` each have their own. Both `FlightTrackingView` and
    /// `MemoryDetailView` are normally reached by pushing onto an existing `NavigationStack`
    /// (Home's flight card, the Memories list), where the system supplies a back chevron
    /// automatically — but here they're the *root* of a brand-new `NavigationStack` inside a
    /// `fullScreenCover` (no push to go back from, and `fullScreenCover` — unlike `sheet` —
    /// has no swipe-to-dismiss either), so without this a widget tap left no way off the screen
    /// at all.
    @ViewBuilder
    private func recordDeepLinkDestination(_ destination: WidgetDeepLink.Destination) -> some View {
        switch destination {
        case .flight(let id):
            Group {
                if let flight = appModel.flights.first(where: { $0.id == id }) {
                    FlightTrackingView(flight: flight)
                } else {
                    GameErrorState(message: "This flight isn't available anymore.")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { recordDeepLink = nil }
                }
            }
        case .trip(let id):
            Group {
                if let trip = appModel.trips.first(where: { $0.id == id }) {
                    TripDetailsView(trip: trip)
                } else {
                    GameErrorState(message: "This trip isn't available anymore.")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { recordDeepLink = nil }
                }
            }
        case .memory(let id):
            Group {
                if let memory = appModel.memories.first(where: { $0.id == id }) {
                    MemoryDetailView(memory: memory)
                } else {
                    GameErrorState(message: "This memory isn't available anymore.")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { recordDeepLink = nil }
                }
            }
        case .drawingPad:
            DrawingPadEditorView()
        case .partnerDrawingPad:
            // The URL is loaded lazily by `DrawingPadCard`, which may never have been on screen
            // — arriving here straight from a notification tap on a cold launch is the normal
            // case, not the edge one. `DrawingPadFullScreenView` shows its own empty state while
            // this resolves, so it opens immediately and fills in rather than gating on a load.
            DrawingPadFullScreenView(title: appModel.partner.name, url: appModel.partnerDrawingURL)
                .task { await appModel.loadDrawingPads() }
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

    /// Same suppression chain as `reviewPromptBinding` above, one step further down: never
    /// compete with the partner-connected celebration or an already-queued review prompt for
    /// the same sheet slot. In practice these two rarely collide (the review prompt's
    /// `partnerConnected`-gated milestones can't fire for a solo user), except `.firstGameResults`
    /// — reachable solo now — which is exactly the case this exists to resolve in the review
    /// prompt's favor.
    private var partnerInviteNudgeBinding: Binding<Bool> {
        Binding(
            get: {
                appModel.pendingPartnerInviteNudge
                    && !showingPartnerConnectedCelebration
                    && appModel.pendingReviewMilestone == nil
            },
            set: { appModel.pendingPartnerInviteNudge = $0 }
        )
    }

    /// Re-reads the OR'd entitlement truth across both partners — see
    /// `BackendService.fetchSubscriptionActive`. No-ops before onboarding is done
    /// (`hasCouple == false`), since there's nothing to gate yet.
    ///
    /// Read-only as of the RevenueCat webhook: this used to push the device's own entitlement to
    /// the profile row first, which is what made the client the source of truth for who had paid.
    ///
    /// Also refreshes `appModel.subscriptionTier`, which is otherwise only ever set at
    /// couple-adoption time — without this, a mid-session upgrade/downgrade left every
    /// `isPremiumLocked`/`isDeckLocked` check reading a stale tier until the next full relaunch.
    private func checkSubscription() async {
        // `defer`, and before the guard: every path out of here has to release the loading state
        // the gate holds on it. An early return, a thrown fetch, or no connectivity at all must end
        // in a real screen — a paywall this cannot decide against is still better than a spinner
        // that never resolves.
        defer { hasCheckedSubscription = true }
        guard appModel.hasCouple else { return }
        // Still refreshed, because `subscriptionStore.subscribedTier` drives the Settings and
        // Customer Center screens — but nothing is written back from it any more.
        await subscriptionStore.refreshEntitlementsOnly()
        if let active = try? await BackendService.fetchSubscriptionActive() {
            // OR'd with this device's own entitlement for the same reason the gate above is: a
            // backend `false` for someone RevenueCat says is subscribed means the webhook has not
            // caught up, not that they stopped paying. Without this the next foreground undoes the
            // access the gate just granted.
            appModel.isSubscriptionActive = active || subscriptionStore.isSubscribed
            OfflineSessionCache.record(
                active: active,
                tier: appModel.subscriptionTier,
                userID: BackendService.currentUserID,
                partnerConnected: appModel.partnerConnected,
                myName: appModel.currentUser.name,
                partnerName: appModel.partner.name,
                celebrationShown: appModel.partnerConnectedCelebrationShown,
                checklistDismissed: appModel.setupChecklistDismissed
            )
        } else if !appModel.isSubscriptionActive,
                  let cached = OfflineSessionCache.restore(for: BackendService.currentUserID),
                  cached.active {
            // The read failed (offline). Fall back to the last confirmed couple-wide answer rather
            // than leaving `false` standing — this runs right after `loadSignedInState`, so
            // without it a foreground refresh mid-flight could undo that restore and re-paywall a
            // subscriber. Only ever upgrades false -> true; a genuine "not subscribed" from the
            // backend above still wins, because that branch takes priority.
            appModel.isSubscriptionActive = true
            appModel.subscriptionTier = cached.tier
        }
        // Falls back to this device's own entitlement when the couple row has no tier yet, so a
        // Premium subscriber isn't shown every premium deck locked while the webhook catches up.
        // Optimistic only — `start_deck_session` enforces the tier server-side from the same
        // profile columns, so a client that is ahead of the row cannot actually open anything.
        if let tier = try? await BackendService.fetchCoupleSubscriptionTier() {
            appModel.subscriptionTier = tier ?? subscriptionStore.subscribedTier?.dbValue
        }
        // Owns its own widget refresh (same convention every other state-mutating `AppModel`
        // method uses — see `performAdopt`, `refreshFlights`, `addMemory`) rather than relying on
        // the separate concurrent refresh `onChange(of: scenePhase)` used to fire alongside this:
        // two independently-scheduled `Task`s have no ordering guarantee, so that refresh could
        // run before this method's tier/active updates landed and ship a stale widget snapshot.
        await WidgetSnapshotWriter.refresh(appModel: appModel)
    }

    /// Unlike most other `IfNeeded` refreshes here, this now needs to stay fresh continuously
    /// rather than stopping once subscribed — it drives Home's persistent "invite pending" card
    /// (and clears it once accepted/declined), not just the pre-subscription gate it used to be
    /// the sole reason for. Still no point fetching before onboarding is done; the (now more
    /// consequential, since a truly connected couple would otherwise poll this every foreground
    /// forever) `!partnerConnected` short-circuit lives in `AppModel.refreshPendingOutgoingConnectionRequest()`
    /// itself, so `PendingConnectionApprovalView`'s own "Check again" call gets it too.
    private func refreshPendingOutgoingConnectionRequestIfNeeded() async {
        guard appModel.hasCouple else { return }
        await appModel.refreshPendingOutgoingConnectionRequest()
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
