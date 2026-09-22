//
//  WebAccountOnboardingTests.swift
//  TwofoldTests
//
//  Somebody who subscribes on the website ends up with a real account they never onboarded.
//
//  The website's sign-in creates an `auth.users` row, `handle_new_user` creates the matching
//  profile, and neither supplies a name — so the account exists with `first_name = ''`, no partner,
//  no anniversary and no invite code. `AppModel.loadSignedInState` used to admit anybody with a
//  session straight into `MainTabView` on the stated reasoning that "being authenticated at all
//  means onboarding is already done", which stopped being true the moment the web could create an
//  account. They arrived called "You", with no way back to the flow that collects any of it.
//
//  What is pinned here is the *variant* flow: the same screens, minus the two stretches that make
//  no sense for an account that already exists and is already paying. Those two skips are the whole
//  risk — getting either wrong means asking a subscriber to create a second account, or charging
//  them twice.
//

import Testing
import Foundation
import SwiftUI
@testable import Twofold

@MainActor
struct WebAccountOnboardingTests {

    @Test("a signed-in app is not routed into onboarding by default")
    func defaultIsNotOnboarding() {
        // The flag gates `hasCouple`, so a wrong default here locks every existing user out of the
        // app and into a flow they finished long ago.
        #expect(AppModel().needsOnboarding == false)
        #expect(OnboardingModel().isResumingAuthenticatedAccount == false)
    }

    // MARK: - Getting back out again

    // The account is created part-way through the flow, at `.saveAccount` — before the invite
    // screen, the trial screen and the paywall, and only `.purchaseSuccess`/`.reveal` record
    // completion. So there is a long stretch, covering the paywall, where someone holds a live
    // session that the server still calls un-onboarded. Quitting or navigating back during it put
    // them on the first onboarding question as a stack root: no back button, and no other way off
    // it. Reinstalling did not clear it, because the session is in the Keychain and outlives the
    // app. A real device got stuck exactly this way.

    @Test("the server's answer alone still routes an un-onboarded account into the flow")
    func serverAnswerRoutesIntoOnboarding() {
        #expect(AppModel.shouldRouteToOnboarding(serverSaysCompleted: false, completedLocally: false))
        #expect(!AppModel.shouldRouteToOnboarding(serverSaysCompleted: true, completedLocally: false))
    }

    @Test("a completion the server never recorded still gets the person into the app")
    func localNoteAdmitsWhenTheWriteWasLost() {
        // The case this exists for: `markOnboardingCompleted()` failed, so the column is still
        // null. Without the note, every launch reads that null and returns them to the question
        // with no back button — the escape would work once and then trap them again.
        #expect(!AppModel.shouldRouteToOnboarding(serverSaysCompleted: false, completedLocally: true))
    }

    @Test("the local note is per-account, so it cannot admit the next person to sign in here")
    func localNoteIsScopedToOneAccount() {
        // Phones get shared, and accounts get signed out of and swapped. A single flat key would
        // wave a brand-new account straight past onboarding it has never done.
        let one = UUID(), two = UUID()
        #expect(AppModel.onboardingCompletedLocallyKey(for: one) != AppModel.onboardingCompletedLocallyKey(for: two))
        #expect(AppModel.onboardingCompletedLocallyKey(for: one) == AppModel.onboardingCompletedLocallyKey(for: one))
    }

    // MARK: - Resuming a dropout

    @Test("an account that got as far as creating itself is offered a resume, not question one")
    func savedProgressPicksTheResumeRoot() {
        // `OnboardingCoordinatorView` picks its root from this pair. Both true is the person who
        // made an account and stopped — overwhelmingly on the paywall, which cannot be dismissed
        // and sits three screens after account creation.
        let model = AppModel()
        model.needsOnboarding = true
        model.hasSavedOnboardingProgress = true

        #expect(model.needsOnboarding && model.hasSavedOnboardingProgress)
    }

    @Test("a website account, which has answered nothing, still starts at question one")
    func webAccountStartsAtTheQuestionnaire() {
        // The distinction the column exists to make. A feedback-board or web-subscription account
        // has a real `profiles` row and no answers in it, so there is nothing to resume and
        // offering to would be a lie.
        let model = AppModel()
        model.needsOnboarding = true
        model.hasSavedOnboardingProgress = false

        #expect(model.needsOnboarding && !model.hasSavedOnboardingProgress)
    }

    @Test("the resume offer does not survive into the next account on this phone")
    func savedProgressIsAccountScoped() {
        // Otherwise the next person to sign in here is shown somebody else's half-finished setup
        // and invited to carry on with it. `AccountScopedStateResetTests` makes the same argument
        // about `needsOnboarding`; this is the flag that decides which root that one shows.
        let model = AppModel()
        model.needsOnboarding = true
        model.hasSavedOnboardingProgress = true

        model.resetAccountScopedState()

        #expect(model.hasSavedOnboardingProgress == false)
    }

    // MARK: - The paywall skip

    @Test("a normal signup is still sold the trial before the paywall")
    func normalFlowReachesPaywall() {
        let onboarding = OnboardingModel()
        #expect(InvitePartnerView.afterInvite(onboarding) == .trialTrust)
    }

    @Test("a web subscriber is not shown a paywall they already paid")
    func resumingFlowSkipsPaywall() {
        let onboarding = OnboardingModel()
        onboarding.isResumingAuthenticatedAccount = true
        onboarding.hasActiveSubscription = true
        // `.reveal` is the existing "you're all set" ending, already used by the redeem path
        // whenever the paywall is skipped — not a new screen invented for this case.
        #expect(InvitePartnerView.afterInvite(onboarding) == .reveal)
    }

    @Test("resuming onboarding is not by itself proof of having paid")
    func resumingWithoutSubscriptionStillReachesPaywall() {
        // The skip used to ask `isResumingAuthenticatedAccount`, on the reasoning that such an
        // account "paid on the web already". It means only that `onboarding_completed_at` is null,
        // which is equally true of somebody who signed in to the website's feedback board (a
        // magic-link page with no checkout in it), of somebody who quit in-app onboarding after
        // `.saveAccount` — which happens *before* this screen — and of a lapsed subscriber.
        //
        // None of them got anything free: the database refuses writes without a subscription
        // (20261028000000). They got an app that silently would not save anything, having never
        // been shown the paywall that would have explained it.
        let onboarding = OnboardingModel()
        onboarding.isResumingAuthenticatedAccount = true
        onboarding.hasActiveSubscription = false

        #expect(InvitePartnerView.afterInvite(onboarding) == .trialTrust)
    }

    @Test("a paid account skips the paywall however it arrived")
    func subscriptionAloneDecidesTheSkip() {
        // The mirror: the question is the subscription, not the route. A subscriber part-way
        // through a normal signup should not be sold what they are already paying for either.
        let onboarding = OnboardingModel()
        onboarding.isResumingAuthenticatedAccount = false
        onboarding.hasActiveSubscription = true

        #expect(InvitePartnerView.afterInvite(onboarding) == .reveal)
    }

    /// Through the real card rather than the helper, so deleting the wiring in `connectCard`
    /// fails here instead of leaving a green test of a function nothing calls.
    @Test("sharing a code as a web subscriber also skips the paywall")
    func sharingSkipsPaywallWhenResuming() {
        let onboarding = OnboardingModel()
        onboarding.isResumingAuthenticatedAccount = true
        // Spelled out now that the skip asks about the subscription rather than about resuming.
        // "Web subscriber" is what this test was always describing; it simply used to be able to
        // say it with the resuming flag, back when that flag was treated as proof of paying.
        onboarding.hasActiveSubscription = true
        onboarding.path = [.invitePartner]

        InvitePartnerView.connectCard(
            onboarding: onboarding, appModel: AppModel(), inviteCode: .constant("ABCD-EFGH")
        ).onInviteShared?()

        #expect(onboarding.path == [.invitePartner, .reveal], "got \(onboarding.path)")
    }

    /// The mirror, through the same card — this is the hard paywall, so the route that was
    /// leaking deserves a test that fails if it ever leaks again.
    @Test("sharing a code without a subscription still leads to the paywall")
    func sharingWithoutSubscriptionKeepsThePaywall() {
        let onboarding = OnboardingModel()
        onboarding.isResumingAuthenticatedAccount = true
        onboarding.hasActiveSubscription = false
        onboarding.path = [.invitePartner]

        InvitePartnerView.connectCard(
            onboarding: onboarding, appModel: AppModel(), inviteCode: .constant("ABCD-EFGH")
        ).onInviteShared?()

        #expect(onboarding.path == [.invitePartner, .trialTrust], "got \(onboarding.path)")
    }

    // MARK: - Starting over

    @Test("a deleted account starts a genuinely fresh flow")
    func deletedAccountClearsTheResumeFlag() {
        // Signing into a deleted account drops back to `WelcomeView`, which only exists as the
        // stack root when this is false. Left set, the reset would land on a flow that assumes an
        // account which no longer exists.
        let onboarding = OnboardingModel()
        onboarding.isResumingAuthenticatedAccount = true

        onboarding.resetAfterDeletedAccount()

        #expect(onboarding.isResumingAuthenticatedAccount == false)
        #expect(onboarding.path.isEmpty)
    }
}
