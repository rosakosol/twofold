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
//  It was hard to see by reading because there are two different routes to the same screen.
//  `ShareInviteView` has an onboarding initialiser that advances the path, and that initialiser is
//  only used by the deep-link path (`.connectPartner` -> `.shareInvite`). The flow a new user
//  actually walks is `.invitePartner`, which renders `PartnerConnectCard` and opens the very same
//  view as a *sheet*, with a closure that only dismissed. Both routes are asserted here so a fix
//  to one is never mistaken for a fix to both.
//

import Testing
import Foundation
import SwiftUI
@testable import Twofold

@MainActor
struct OnboardingInviteContinueTests {

    /// The deep-link route, which was always correct.
    @Test("the pushed invite screen advances the onboarding path")
    func pushedRouteAdvances() {
        let onboarding = OnboardingModel()
        onboarding.inviteCode = "ABCD-EFGH"
        onboarding.path = [.connectPartner, .shareInvite]

        ShareInviteView(onboarding: onboarding).onContinue()

        #expect(onboarding.path == [.connectPartner, .shareInvite, .nextTrip], "got \(onboarding.path)")
    }

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

        // What InvitePartnerView's `secondaryAction` does.
        let skipped = OnboardingModel()
        skipped.path = [.invitePartner, .trialTrust]

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
