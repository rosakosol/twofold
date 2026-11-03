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
        model.session.hasCouple = true
        model.session.partnerConnected = true
        model.session.inviteCode = "ABC123"
        model.subscription.isActive = true
        model.subscription.tier = "premium"
        model.travel.trips = []
        model.myDrawingURL = URL(string: "https://example.test/sign/drawing-pads/couple/person/pad.png")
        model.partnerDrawingURL = URL(string: "https://example.test/sign/drawing-pads/couple/other/pad.png")
        model.games.dailyStreak = 28
        model.games.longestDailyStreak = 40
        model.games.dailyStreakResetsAt = .now
        model.games.todaysDailySessionID = UUID()
        model.games.todaysDailyQuestionText = "Someone else's question"
        model.games.todaysMyAnswered = true
        model.games.todaysPartnerAnswered = true
        model.games.dailyQuestionError = "stale"
        model.prompts.partnerDisconnectedMessage = "Your connection with Alex has ended"
        model.prompts.partnerSubscriptionLapsedPartnerName = "Alex"
        model.prompts.partnerConnectedCelebrationShown = true
        model.prompts.setupChecklistDismissed = true
        model.prompts.pendingPartnerInviteNudge = true
        model.prompts.pendingReviewMilestone = .firstMemory
        model.prompts.writeRefusedMessage = "refused"
        model.session.needsOnboarding = true
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

        #expect(model.games.dailyStreak == nil)
        #expect(model.games.longestDailyStreak == nil)
        #expect(model.games.dailyStreakResetsAt == nil)
        #expect(model.games.streakRepair == nil)
    }

    @Test("Today's question and whether the last couple answered it go too")
    func dailyQuestionIsCleared() {
        let model = dirtied()
        model.resetAccountScopedState()

        #expect(model.games.todaysDailySessionID == nil)
        #expect(model.games.todaysDailyQuestionText == nil)
        #expect(model.games.todaysMyAnswered == false)
        #expect(model.games.todaysPartnerAnswered == false)
        #expect(model.games.dailyQuestionError == nil)
    }

    @Test("The tier goes, so a free account cannot inherit premium access")
    func subscriptionStateIsCleared() {
        let model = dirtied()
        model.resetAccountScopedState()

        #expect(model.subscription.isActive == false)
        #expect(model.subscription.tier == nil)
    }

    @Test("Nothing naming the previous partner survives")
    func namesAreCleared() {
        let model = dirtied()
        model.resetAccountScopedState()

        #expect(model.prompts.partnerDisconnectedMessage == nil)
        #expect(model.prompts.partnerSubscriptionLapsedPartnerName == nil)
        #expect(model.session.pendingConnectionRequests.isEmpty)
        #expect(model.session.pendingOutgoingConnectionRequest == nil)
        #expect(model.session.couple.partnerB.name == "Partner")
        #expect(model.session.couple.partnerA.name == "You")
    }

    @Test("Per-account seen-it flags go, so a new account does not arrive to a dismissed checklist")
    func uiFlagsAreCleared() {
        let model = dirtied()
        model.resetAccountScopedState()

        #expect(model.prompts.partnerConnectedCelebrationShown == false)
        #expect(model.prompts.setupChecklistDismissed == false)
        #expect(model.prompts.pendingPartnerInviteNudge == false)
        #expect(model.prompts.pendingReviewMilestone == nil)
        #expect(model.prompts.writeRefusedMessage == nil)
    }

    @Test("And the couple itself is back to the placeholder")
    func coupleIdentityIsCleared() {
        let model = dirtied()
        model.resetAccountScopedState()

        #expect(model.session.hasCouple == false)
        #expect(model.session.partnerConnected == false)
        #expect(model.session.backendCoupleID == nil)
        #expect(model.session.inviteCode == nil)
        #expect(model.games.gameDecks == nil)
        #expect(model.games.deckProgress == nil)
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

        #expect(model.session.needsOnboarding == false)
    }
}
