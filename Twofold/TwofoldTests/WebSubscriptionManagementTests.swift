//
//  WebSubscriptionManagementTests.swift
//  TwofoldTests
//
//  A web subscriber opening Settings was told their partner was paying.
//
//  The banner's branches were "this device's own entitlement", then "the row says covered", then
//  "sell them something". A subscription bought on twofoldapp.com.au satisfies the second and not
//  the first — the entitlement lives on RevenueCat's website customer, not in this device's StoreKit
//  receipts — so every web subscriber fell into the partner case, including those with no partner at
//  all. The screen named a partner who was not paying, said only they could cancel, and offered no
//  way to reach the portal that actually can. `CustomerCenterView` was no use either: it knows this
//  device's purchase history and nothing else, which is why that branch exists in the first place.
//
//  `profiles.subscription_store` has recorded where each subscription was bought since migration
//  20261109000500, and the website has read it since the account portal shipped. iOS never did.
//

import Testing
@testable import Twofold

struct WebSubscriptionManagementTests {

    // MARK: - Which screen the banner opens

    /// The reported case, and the one with no partner to blame.
    @Test("a website subscriber is sent to the website, not to their partner")
    func webSubscriberIsSentToTheWeb() {
        #expect(
            SettingsView.subscriptionDestination(
                deviceHoldsEntitlement: false,
                coupleIsCovered: true,
                viewerHoldsSubscription: true,
                viewerSubscriptionStore: "rc_billing"
            ) == .manageOnWeb
        )
    }

    /// The case that branch was written for, which must keep working — the row is couple-wide, so
    /// the non-payer's access comes from a purchase that is genuinely not theirs to end.
    @Test("the partner who didn't pay still gets the partner screen")
    func partnerCoveredStillGetsThePartnerScreen() {
        #expect(
            SettingsView.subscriptionDestination(
                deviceHoldsEntitlement: false,
                coupleIsCovered: true,
                viewerHoldsSubscription: false,
                viewerSubscriptionStore: nil
            ) == .partnerManages
        )
    }

    /// The staleness trap, and the reason `viewerHoldsSubscription` guards the store rather than
    /// the store being read on its own. `subscription_store` is left behind when a subscription
    /// lapses, exactly as `subscription_tier` is. Reading it alone would send this person to cancel
    /// something that ended months ago and never mention the subscription actually covering them.
    @Test("a lapsed web subscription doesn't outrank the partner now paying")
    func staleWebStoreDoesNotOutrankThePayingPartner() {
        #expect(
            SettingsView.subscriptionDestination(
                deviceHoldsEntitlement: false,
                coupleIsCovered: true,
                viewerHoldsSubscription: false,
                viewerSubscriptionStore: "rc_billing"
            ) == .partnerManages
        )
    }

    /// Both at once is possible — the casing split that made two RevenueCat customers out of one
    /// person is exactly how somebody ends up paying twice. The live one is the one to offer.
    @Test("this device's own subscription wins over a recorded web one")
    func deviceEntitlementWinsOverARecordedWebStore() {
        #expect(
            SettingsView.subscriptionDestination(
                deviceHoldsEntitlement: true,
                coupleIsCovered: true,
                viewerHoldsSubscription: true,
                viewerSubscriptionStore: "rc_billing"
            ) == .customerCenter
        )
    }

    /// An App Store subscription bought on the buyer's *other* device: covered, nothing local, and
    /// not a web purchase. There is nothing honest to offer but the partner screen, and sending them
    /// to the website would be the false-positive this defaults away from.
    @Test("an App Store purchase is never sent to the website")
    func appStorePurchaseIsNeverSentToTheWebsite() {
        #expect(
            SettingsView.subscriptionDestination(
                deviceHoldsEntitlement: false,
                coupleIsCovered: true,
                viewerHoldsSubscription: true,
                viewerSubscriptionStore: "app_store"
            ) == .partnerManages
        )
    }

    @Test("nobody is covered, so the banner still sells")
    func uncoveredStillSells() {
        #expect(
            SettingsView.subscriptionDestination(
                deviceHoldsEntitlement: false,
                coupleIsCovered: false,
                viewerHoldsSubscription: false,
                viewerSubscriptionStore: nil
            ) == .paywall
        )
    }

    // MARK: - What counts as a web store

    @Test("both RevenueCat web stores count", arguments: ["stripe", "rc_billing", "RC_BILLING", " Stripe "])
    func webStoresCount(_ store: String) {
        #expect(AppModel.isWebManagedStore(store))
    }

    /// Nil is the common answer, not an edge case: every subscription older than migration
    /// 20261109000500 has nothing recorded until its next webhook, and a cold offline launch has
    /// nothing at all. It must never read as a web store.
    @Test("anything not positively a web store isn't one", arguments: [nil, "", "   ", "app_store", "play_store", "promotional", "mac_app_store", "amazon", "unknown"])
    func everythingElseIsNot(_ store: String?) {
        #expect(!AppModel.isWebManagedStore(store))
    }
}
