//
//  PaywallGateTests.swift
//  TwofoldTests
//
//  A forced paywall shown to someone who already holds an entitlement is not a prompt, it is a dead
//  end. `PaywallView` has nothing to sell them: their own tier renders "Current Plan" with the CTA
//  disabled, the other tier renders "Manage Subscription", and neither leads into the app.
//
//  That happened to a real subscriber. The gate read only `profiles.subscription_active`, which is a
//  cache written by `revenuecat-webhook` — and between a purchase completing and that webhook
//  landing (or while it is misconfigured, as it was) the row says `false` for someone who has paid.
//  RevenueCat said Premium; the row said nothing; the app showed a paywall with every button dead.
//
//  So the gate also accepts this device's own live entitlement. That is not a bypass:
//  `customerInfo.entitlements.active` is RevenueCat's own receipt-validated answer, the same source
//  the webhook reads. What the client still may not do is *write* it — that is the paywall bypass
//  migration 20260915000000 closed, and it stays closed.
//

import Testing
@testable import Twofold

struct PaywallGateTests {

    /// The reported case: paid, entitled on this device, and the backend hasn't caught up.
    @Test("a paid subscriber gets in before the webhook has written the row")
    func liveEntitlementGrantsAccessAheadOfTheBackend() {
        #expect(RootView.hasAccess(backendSaysActive: false, deviceHoldsEntitlement: true, awaitingPartnerDecision: false))
    }

    /// The negative control. Without the middle term this is exactly the dead end — and it is the
    /// term most likely to look redundant to someone tidying the condition later.
    @Test("without the device's own entitlement, that subscriber is locked out")
    func backendAloneLocksOutAPaidSubscriber() {
        #expect(!RootView.hasAccess(backendSaysActive: false, deviceHoldsEntitlement: false, awaitingPartnerDecision: false))
    }

    /// The ordinary path, and the one that keeps working for the partner who didn't pay: the row is
    /// couple-wide, so their device holds no entitlement of its own and access comes from the OR
    /// across both profiles.
    @Test("a partner with no entitlement of their own still gets in on the couple's row")
    func backendGrantsAccessToTheNonPayingPartner() {
        #expect(RootView.hasAccess(backendSaysActive: true, deviceHoldsEntitlement: false, awaitingPartnerDecision: false))
    }

    /// Redeemed an invite and waiting on the inviter — they have no subscription of their own and
    /// are not meant to be asked for one.
    @Test("someone awaiting a partner's decision is not asked to subscribe")
    func pendingRequestGrantsAccess() {
        #expect(RootView.hasAccess(backendSaysActive: false, deviceHoldsEntitlement: false, awaitingPartnerDecision: true))
    }

    /// And the paywall still has to appear for someone who genuinely has not paid, or this stops
    /// being a gate at all.
    @Test("nobody paying means the paywall")
    func noSignalMeansPaywall() {
        #expect(!RootView.hasAccess(backendSaysActive: false, deviceHoldsEntitlement: false, awaitingPartnerDecision: false))
    }
}

//
//  The third state: we don't know yet.
//
//  `pendingOutgoingConnectionRequest == nil` means both "there is no pending request" and "we have
//  not asked yet", and the gate has to tell those apart. At launch the lookup is a network round
//  trip that lands after `hasCouple` flips true, so the gate evaluated in between and flashed a
//  paywall at the one person who is explicitly exempt from it — someone who redeemed an invite and
//  is waiting on the inviter to accept.
//
@MainActor
struct PaywallExemptionResolutionTests {

    /// Stands in for the launch sequence: what the gate would decide at each step.
    private func decision(resolved: Bool, pendingRequest: Bool) -> String {
        if RootView.hasAccess(backendSaysActive: false, deviceHoldsEntitlement: false, awaitingPartnerDecision: pendingRequest) {
            return "app"
        }
        return resolved ? "paywall" : "loading"
    }

    /// The bug: mid-launch, before the lookup lands, an exempt invitee must not see a paywall.
    @Test("an unresolved lookup shows loading, not a paywall")
    func unresolvedShowsLoading() {
        #expect(decision(resolved: false, pendingRequest: false) == "loading")
    }

    /// And once it lands, they go straight into the app — never having seen a price.
    @Test("a resolved pending request opens the app")
    func resolvedPendingOpensApp() {
        #expect(decision(resolved: true, pendingRequest: true) == "app")
    }

    /// Someone with no request and nothing paid still gets the paywall, once we actually know.
    @Test("a resolved absence shows the paywall")
    func resolvedAbsenceShowsPaywall() {
        #expect(decision(resolved: true, pendingRequest: false) == "paywall")
    }

    /// The negative control. Treating "not asked yet" as "no request" is precisely the old
    /// behaviour, and it puts a paywall in front of the invitee.
    @Test("treating unknown as absent is what showed the paywall")
    func unknownAsAbsentIsTheBug() {
        // What the gate did before: no third state, so unresolved fell through to the paywall.
        let old = RootView.hasAccess(backendSaysActive: false, deviceHoldsEntitlement: false, awaitingPartnerDecision: false)
        #expect(!old, "with no way to say 'unknown', an exempt invitee is shown a paywall")
    }
}

//
//  The same third state, for the subscription itself.
//
//  Both of the gate's real terms are false at launch before anything has checked them, and neither
//  is a reliable "no":
//
//    * `isSubscriptionActive` is applied from the offline cache, then overwritten by
//      `loadSignedInState` with the bare `profiles.subscription_active` row — `false` for anyone
//      whose webhook is behind.
//    * `subscriptionStore.isSubscribed` reads `subscribedTier`, which starts nil and is only filled
//      by `refreshEntitlementsOnly()` — the first line of `checkSubscription()`, and a network fetch.
//
//  So the OR that PaywallGateTests exists to protect cannot help here: during the window both of
//  its terms are false, for reasons that have nothing to do with whether the person has paid. A
//  subscriber saw a forced paywall on every launch and watched it disappear a round trip later.
//
@MainActor
struct SubscriptionResolutionGateTests {

    /// The gate's branch order, as the launch sequence walks through it.
    private func decision(
        subscriptionChecked: Bool,
        requestResolved: Bool = true,
        backendSaysActive: Bool = false,
        deviceHoldsEntitlement: Bool = false,
        pendingRequest: Bool = false
    ) -> String {
        if RootView.hasAccess(
            backendSaysActive: backendSaysActive,
            deviceHoldsEntitlement: deviceHoldsEntitlement,
            awaitingPartnerDecision: pendingRequest
        ) {
            return "app"
        }
        if !subscriptionChecked { return "loading" }
        if !requestResolved { return "loading" }
        return "paywall"
    }

    /// The reported bug, at the exact instant it happened: `loadSignedInState` has just written a
    /// stale `false` over the cached answer, and `refreshEntitlementsOnly` has not returned yet.
    @Test("mid-launch, before anything has checked, a subscriber sees loading rather than a paywall")
    func unresolvedSubscriptionShowsLoading() {
        #expect(decision(subscriptionChecked: false) == "loading")
    }

    /// What made this worth a third state rather than another term in the OR: during the window
    /// both existing terms are false, so no amount of OR-ing them rescues it.
    @Test("both gate terms are false in that window, so the OR cannot fix it")
    func theOrCannotCoverTheWindow() {
        let duringLaunch = RootView.hasAccess(
            backendSaysActive: false,      // stale row, webhook behind
            deviceHoldsEntitlement: false, // refreshEntitlementsOnly hasn't returned
            awaitingPartnerDecision: false
        )
        #expect(!duringLaunch, "neither term can distinguish 'not yet known' from 'not paid'")
        // Which is why the branch, not the condition, is what changed.
        #expect(decision(subscriptionChecked: false) == "loading")
    }

    /// Once the check lands and confirms them, they were never shown a price.
    @Test("a confirmed subscriber goes straight in")
    func checkedAndActiveOpensApp() {
        #expect(decision(subscriptionChecked: true, backendSaysActive: true) == "app")
    }

    /// And the gate still closes on someone who genuinely has not paid — one round trip later,
    /// which is the right way round.
    @Test("a checked absence still shows the paywall")
    func checkedAndInactiveShowsPaywall() {
        #expect(decision(subscriptionChecked: true) == "paywall")
    }

    /// The guard must never outlive the check that clears it. `checkSubscription` sets the flag in
    /// a `defer` ahead of its own `guard`, so an early return or a failed fetch still resolves —
    /// otherwise "we don't know yet" becomes a spinner nobody can get past.
    @Test("a failed or skipped check still resolves, rather than holding the spinner")
    func aFailedCheckStillResolves() {
        // What the defer guarantees: checked is true even when nothing could be learned.
        #expect(decision(subscriptionChecked: true) == "paywall")
    }

    /// The previous behaviour, kept as the negative control: with no third state the same instant
    /// fell through to the forced paywall.
    @Test("treating unchecked as unsubscribed is what flashed the paywall")
    func uncheckedAsUnsubscribedIsTheBug() {
        func oldDecision() -> String {
            RootView.hasAccess(backendSaysActive: false, deviceHoldsEntitlement: false, awaitingPartnerDecision: false)
                ? "app" : "paywall"
        }
        #expect(oldDecision() == "paywall")
        #expect(decision(subscriptionChecked: false) == "loading")
    }
}
