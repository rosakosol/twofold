//
//  OnboardingInviteContinueTests.swift
//  TwofoldTests
//
//  "Continue to Twofold", on the screen that shows someone their invite code.
//
//  The bug this pins: in the default sign-up flow that button did nothing but close the sheet it
//  was in, dropping the user back on the invite screen — whose only remaining way forward was
//  labelled "Not now", offered to someone who had just shared their code. Onboarding stopped
//  there.
//
//  It was hard to see by reading because there used to be two routes to the same screen: a pushed
//  `.shareInvite` step that advanced the path, and the one a new user actually walks,
//  `.invitePartner`, which renders `PartnerConnectCard` and opens the very same view as a *sheet*,
//  with a closure that only dismissed. The pushed route could no longer be reached and has been
//  removed; the sheet route is the one asserted here.
//

import Testing
import Foundation
import SwiftUI
@testable import Twofold

@MainActor
struct OnboardingInviteContinueTests {

    /// The route a new signing-up user actually takes, through the real card `InvitePartnerView`
    /// builds. An earlier version of this test constructed the continuation inline and called it,
    /// which asserted nothing about the app — a control that deleted the wiring left it green.
    @Test("the sheet route carries on through onboarding")
    func sheetRouteContinues() {
        let onboarding = OnboardingModel()
        onboarding.path = [.invitePartner]

        let card = InvitePartnerView.connectCard(
            onboarding: onboarding,
            appModel: AppModel(),
            inviteCode: .constant("ABCD-EFGH")
        )
        let onInviteShared = try? #require(card.onInviteShared)
        onInviteShared?()

        #expect(onboarding.path == [.invitePartner, .trialTrust], "got \(onboarding.path)")
    }

    /// Where it goes is deliberately the same place "Not now" goes: sharing a code connects
    /// nobody yet, so the inviter carries on through onboarding exactly as they would have. Both
    /// sides read from the app rather than from this test, so the two cannot drift apart without
    /// this failing.
    @Test("sharing and skipping lead to the same next step")
    func sharingAndSkippingAgree() {
        let shared = OnboardingModel()
        shared.path = [.invitePartner]
        InvitePartnerView.connectCard(
            onboarding: shared, appModel: AppModel(), inviteCode: .constant("ABCD-EFGH")
        ).onInviteShared?()

        // What InvitePartnerView's `secondaryAction` does — read from the app, not copied. It used
        // to be the literal `[.invitePartner, .trialTrust]`, which quietly stopped being a check
        // that the two routes agree the moment either one could branch.
        let skipped = OnboardingModel()
        skipped.path = [.invitePartner, InvitePartnerView.afterInvite(skipped)]

        #expect(shared.path == skipped.path)
    }

    /// The card is used post-onboarding too — PartnerSetupView and PartnerRequiredGateView — where
    /// there is nowhere to continue to and closing the sheet is the whole action. An optional
    /// continuation is what lets one component mean both things.
    @Test("outside onboarding there is no continuation")
    func noContinuationOutsideOnboarding() {
        let card = PartnerConnectCard(inviteCode: .constant("ABCD-EFGH"))
        #expect(card.onInviteShared == nil, "the shared card must not assume an onboarding flow")
    }
}
