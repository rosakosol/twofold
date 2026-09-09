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
