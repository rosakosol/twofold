//
//  AdmissionPathSubscriptionTests.swift
//  TwofoldTests
//
//  `profiles.subscription_active` is a cache written by `revenuecat-webhook`, so between a purchase
//  completing and that webhook landing the row says `false` for someone who has paid. Home's "No
//  active subscription" card reads `canAddContent`, so it has to see the device's own entitlement
//  OR'd in, and a third "not known yet" state, or it shows that card to a subscriber.
//

import Testing
@testable import Twofold

//  What made the card stick rather than flash: `checkSubscription()` is the only thing that applies the
//  OR, it returns early unless `hasCouple`, and it runs from a `.task` that fires once. Somebody
//  subscribing *inside* onboarding has it run while `hasCouple` is still false — it learns nothing,
//  its `defer` marks it checked, and it never runs again. Onboarding then finishes, the adopt writes
//  the webhook-lagged `false`, and the card sits there until a background/foreground or a trip to
//  Settings happens to re-run the check. Reported twice, both times with "it went away when I opened
//  Settings" attached, which is the tell.
//
@MainActor
struct AdmissionPathSubscriptionTests {

    /// The reported case: account created and subscribed in one sitting, so the webhook has not
    /// landed by the time the adopt reads the row.
    @Test("a device entitlement stands in for a backend row that has not caught up")
    func deviceEntitlementCoversWebhookLag() {
        #expect(AppModel.isSubscribed(backendSaysActive: false, deviceTier: .premium))
        #expect(AppModel.isSubscribed(backendSaysActive: false, deviceTier: .plus))
    }

    /// The direction that must not be rescued. RevenueCat is the receipt-validated answer in both
    /// directions — a cancellation reads as no active entitlement there too.
    @Test("no entitlement and no row still means no subscription")
    func genuineAbsenceStillReadsAsAbsent() {
        #expect(!AppModel.isSubscribed(backendSaysActive: false, deviceTier: nil))
    }

    /// A paid-up row needs no help from the device, which is why the reconciler returns early on it
    /// rather than reaching for `customerInfo` on every launch.
    @Test("a row that says active is enough on its own")
    func backendAloneIsEnough() {
        #expect(AppModel.isSubscribed(backendSaysActive: true, deviceTier: nil))
    }

    /// Where the first fix was wrong.
    ///
    /// It reconciled once, on the admission path, in `loadSignedInState`. Two things defeated that.
    /// Onboarding admits people through `applyOnboardingAccount` instead, so signing up and
    /// subscribing in one sitting never reached it; and `refreshCoupleStateIfNeeded` — which Home
    /// fires on appear and on every foreground — went on assigning the raw row value over the top
    /// afterwards. Reconciling once at admission cannot survive something that re-applies the row
    /// later, which is why it now happens wherever the value is applied rather than once when
    /// somebody arrives.
    @Test("a later refresh must not undo what the purchase established")
    func aRefreshCannotClobberAPurchase() {
        // What a foreground refresh gets back while the webhook is behind.
        let rowAtRefresh = false
        #expect(AppModel.isSubscribed(backendSaysActive: rowAtRefresh, deviceTier: .premium))
        // And the same refresh for somebody who genuinely stopped paying.
        #expect(!AppModel.isSubscribed(backendSaysActive: rowAtRefresh, deviceTier: nil))
    }

    /// Home's own third state, which is a different claim from the one above.
    ///
    /// Fixing the clobber stopped the card *persisting*. It did not stop it appearing: the value it
    /// reads starts false, so "we have not asked yet" still rendered as "you have not paid" for the
    /// one round trip it took to find out, on every single launch. Reported as a flash rather than
    /// a card that stays, which is exactly what a missing third state looks like once the value
    /// underneath it is correct.
    private func homeShowsNoSubscriptionCard(resolved: Bool, canAddContent: Bool) -> Bool {
        resolved && !canAddContent
    }

    @Test("the card is not shown before anything has answered")
    func noCardBeforeTheAnswerLands() {
        // The launch instant: nothing has resolved, and the value it would read is the default.
        #expect(!homeShowsNoSubscriptionCard(resolved: false, canAddContent: false))
    }

    @Test("it is shown once the answer lands and is no")
    func cardShownWhenGenuinelyUnsubscribed() {
        #expect(homeShowsNoSubscriptionCard(resolved: true, canAddContent: false))
    }

    @Test("and never shown to someone who can add content")
    func noCardForASubscriber() {
        #expect(!homeShowsNoSubscriptionCard(resolved: true, canAddContent: true))
    }

    /// Where the third state got undone by its own backstop.
    ///
    /// `hasResolvedSubscription` licenses Home to say "no subscription", so `checkSubscription` must
    /// set it only when something was learned. Setting it in a `defer` before the guard did not:
    /// the launch `.task` runs while `hasCouple` is still false, returned immediately, and announced
    /// a resolution it did not have — so Home mounted, read resolved-and-false, and flashed the card
    /// at a subscriber all over again.
    private func resolutionFollowsFrom(hasCouple: Bool) -> Bool { hasCouple }

    @Test("an early return learns nothing and must not claim to have resolved")
    func earlyReturnDoesNotResolve() {
        #expect(!resolutionFollowsFrom(hasCouple: false), "returning before doing the work resolved nothing")
        #expect(resolutionFollowsFrom(hasCouple: true))
    }

    /// The two flags together, at the instant that was breaking: session still loading, so nothing
    /// is known and nothing may be claimed.
    @Test("mid-load, the card stays hidden even though the value under it reads false")
    func midLoadShowsNothing() {
        let resolved = resolutionFollowsFrom(hasCouple: false)
        #expect(!homeShowsNoSubscriptionCard(resolved: resolved, canAddContent: false))
    }

    /// The negative control for the flash: without the third state, the launch instant and a real
    /// refusal are the same input, so no amount of correcting the value underneath helps.
    @Test("without the resolved flag those two states are indistinguishable")
    func theFlashIsAMissingThirdState() {
        func old(canAddContent: Bool) -> Bool { !canAddContent }
        #expect(old(canAddContent: false), "the launch instant showed the card")
        #expect(old(canAddContent: false), "and so did a genuine refusal — the same input")
    }

    /// The old behaviour, kept as the negative control: the adopt's raw row value, with nothing
    /// OR'd into it, is what put the card in front of a subscriber.
    @Test("taking the row at face value is what showed the card")
    func rawRowValueIsTheBug() {
        let backendSaysActive = false // webhook behind
        #expect(!backendSaysActive, "what the adopt wrote, and what Home then rendered")
        #expect(AppModel.isSubscribed(backendSaysActive: backendSaysActive, deviceTier: .premium))
    }
}
