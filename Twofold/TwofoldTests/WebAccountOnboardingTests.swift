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
        // `.reveal` is the existing "you're all set" ending, already used by the redeem path
        // whenever the paywall is skipped — not a new screen invented for this case.
        #expect(InvitePartnerView.afterInvite(onboarding) == .reveal)
    }

    /// Through the real card rather than the helper, so deleting the wiring in `connectCard`
    /// fails here instead of leaving a green test of a function nothing calls.
    @Test("sharing a code as a web subscriber also skips the paywall")
    func sharingSkipsPaywallWhenResuming() {
        let onboarding = OnboardingModel()
        onboarding.isResumingAuthenticatedAccount = true
        onboarding.path = [.invitePartner]

        InvitePartnerView.connectCard(
            onboarding: onboarding, appModel: AppModel(), inviteCode: .constant("ABCD-EFGH")
        ).onInviteShared?()

        #expect(onboarding.path == [.invitePartner, .reveal], "got \(onboarding.path)")
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
