//
//  AccountScopedStateResetTests.swift
//  TwofoldTests
//
//  What has to be gone from memory before another account signs in on this device.
//
//  This exists because of a real leak: a new account joining a new couple saw the *previous*
//  account's drawing pad on its Home screen and the previous couple's 28-day streak in Games.
//  `clearLocalSessionState()` was thorough about caches — disk, widgets, notifications, SDKs — and
//  had been extended a property at a time as each in-memory leak was noticed, which meant the
//  default for a newly added property was to be forgotten. Twenty-four of AppModel's thirty-two
//  stored properties survived sign-out.
//
//  The drawing pad was the worst of them, because `myDrawingURL` and `partnerDrawingURL` hold
//  *signed Storage URLs*: the next account did not merely show a cached thumbnail, it fetched the
//  previous couple's drawing over the network from a URL that was still valid.
//
//  So this asserts the whole set rather than the two that were reported. A property added later
//  and not reset should fail here.
//

import Foundation
import Testing
@testable import Twofold

@Suite("Account-scoped state is reset before another account signs in")
@MainActor
struct AccountScopedStateResetTests {

    /// Fills every account-scoped property with something recognisable, so "still set" is
    /// distinguishable from "happened to be the default already".
    private func dirtied() -> AppModel {
        let model = AppModel()
        model.hasCouple = true
        model.partnerConnected = true
        model.inviteCode = "ABC123"
        model.isSubscriptionActive = true
        model.subscriptionTier = "premium"
        model.trips = []
        model.myDrawingURL = URL(string: "https://example.test/sign/drawing-pads/couple/person/pad.png")
        model.partnerDrawingURL = URL(string: "https://example.test/sign/drawing-pads/couple/other/pad.png")
        model.dailyStreak = 28
        model.longestDailyStreak = 40
        model.dailyStreakResetsAt = .now
        model.todaysDailySessionID = UUID()
        model.todaysDailyQuestionText = "Someone else's question"
        model.todaysMyAnswered = true
        model.todaysPartnerAnswered = true
        model.dailyQuestionError = "stale"
        model.partnerDisconnectedMessage = "Your connection with Alex has ended"
        model.partnerSubscriptionLapsedPartnerName = "Alex"
        model.partnerConnectedCelebrationShown = true
        model.setupChecklistDismissed = true
        model.pendingPartnerInviteNudge = true
        model.pendingReviewMilestone = .firstMemory
        model.writeRefusedMessage = "refused"
        model.needsOnboarding = true
        return model
    }

    @Test("The drawing pad URLs go, because they are signed URLs to someone else's content")
    func drawingPadURLsAreCleared() {
        let model = dirtied()
        model.resetAccountScopedState()

        #expect(model.myDrawingURL == nil)
        #expect(model.partnerDrawingURL == nil)
    }

    @Test("The streak goes, rather than flickering from the last couple's number")
    func streakIsCleared() {
        let model = dirtied()
        model.resetAccountScopedState()

        #expect(model.dailyStreak == nil)
        #expect(model.longestDailyStreak == nil)
        #expect(model.dailyStreakResetsAt == nil)
        #expect(model.streakRepair == nil)
    }

    @Test("Today's question and whether the last couple answered it go too")
    func dailyQuestionIsCleared() {
        let model = dirtied()
        model.resetAccountScopedState()

        #expect(model.todaysDailySessionID == nil)
        #expect(model.todaysDailyQuestionText == nil)
        #expect(model.todaysMyAnswered == false)
        #expect(model.todaysPartnerAnswered == false)
        #expect(model.dailyQuestionError == nil)
    }

    @Test("The tier goes, so a free account cannot inherit premium access")
    func subscriptionStateIsCleared() {
        let model = dirtied()
        model.resetAccountScopedState()

        #expect(model.isSubscriptionActive == false)
        #expect(model.subscriptionTier == nil)
    }

    @Test("Nothing naming the previous partner survives")
    func namesAreCleared() {
        let model = dirtied()
        model.resetAccountScopedState()

        #expect(model.partnerDisconnectedMessage == nil)
        #expect(model.partnerSubscriptionLapsedPartnerName == nil)
        #expect(model.pendingConnectionRequests.isEmpty)
        #expect(model.pendingOutgoingConnectionRequest == nil)
        #expect(model.couple.partnerB.name == "Partner")
        #expect(model.couple.partnerA.name == "You")
    }

    @Test("Per-account seen-it flags go, so a new account does not arrive to a dismissed checklist")
    func uiFlagsAreCleared() {
        let model = dirtied()
        model.resetAccountScopedState()

        #expect(model.partnerConnectedCelebrationShown == false)
        #expect(model.setupChecklistDismissed == false)
        #expect(model.pendingPartnerInviteNudge == false)
        #expect(model.pendingReviewMilestone == nil)
        #expect(model.writeRefusedMessage == nil)
    }

    @Test("And the couple itself is back to the placeholder")
    func coupleIdentityIsCleared() {
        let model = dirtied()
        model.resetAccountScopedState()

        #expect(model.hasCouple == false)
        #expect(model.partnerConnected == false)
        #expect(model.backendCoupleID == nil)
        #expect(model.inviteCode == nil)
        #expect(model.gameDecks == nil)
        #expect(model.deckProgress == nil)
    }

    /// Its own test rather than a line in `uiFlagsAreCleared`, because the consequence is not a
    /// stale flag — it is being unable to leave.
    ///
    /// `needsOnboarding` picks `OnboardingCoordinatorView`'s root: true gives the first onboarding
    /// question, false gives `WelcomeView`. The first question is presented as a stack root, so it
    /// has no back button, and it offers nothing but the four answers. Signing out while it was
    /// set therefore returned to that same screen, with no sign-in button anywhere — a real device
    /// got stuck there, and reinstalling did not help, because the Supabase session lives in the
    /// Keychain and survives app deletion.
    @Test("Signing out returns to Welcome, not to the first onboarding question")
    func onboardingRoutingIsCleared() {
        let model = dirtied()
        model.resetAccountScopedState()

        #expect(model.needsOnboarding == false)
    }
}
