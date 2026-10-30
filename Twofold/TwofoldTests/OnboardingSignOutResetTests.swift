//
//  OnboardingSignOutResetTests.swift
//  TwofoldTests
//
//  Signing out mid-onboarding has to start the next person from nothing.
//
//  `OnboardingCoordinatorView` holds its `OnboardingModel` as `@State` and stays mounted across a
//  sign-out, because `hasCouple` is false on both sides of it. Nothing reset that model, so the
//  onboarding paywall's "Sign out" left a signed-out user on the paywall (path still ending in
//  `.paywall`), and "Go back" / "Start a new signup" kept the previous account's names, photos
//  and invite code for whoever tapped "Get started" next.
//
//  The coordinator now replaces the model whenever `AppModel.accountGeneration` moves, so what is
//  pinned here is that every account-ending path moves it, every time.
//

import Foundation
import Testing
@testable import Twofold

@Suite("Signing out resets onboarding")
@MainActor
struct OnboardingSignOutResetTests {

    @Test("resetting account state advances the generation the coordinator watches")
    func resetAdvancesGeneration() {
        let model = AppModel()
        model.needsOnboarding = true
        model.hasSavedOnboardingProgress = true
        let before = model.accountGeneration

        model.resetAccountScopedState()

        #expect(model.accountGeneration != before)
    }

    /// A second sign-out in the same launch must still be seen. `onChange` fires on a change of
    /// value, so a flag that was set once and never cleared would only work the first time.
    @Test("every reset is a new generation, not just the first")
    func everyResetCounts() {
        let model = AppModel()
        model.resetAccountScopedState()
        let afterFirst = model.accountGeneration
        model.resetAccountScopedState()
        #expect(model.accountGeneration != afterFirst)
    }

    /// The new field the paywall writes has to be part of the deleted-account wipe as well, the
    /// list that `resetAfterDeletedAccount()` keeps by hand.
    @Test("the deleted-account wipe clears the subscription outcome")
    func deletedAccountWipeClearsOutcome() {
        let model = OnboardingModel()
        model.path = [.invitePartner, .trialTrust, .paywall]
        model.subscriptionOutcome = .restored

        model.resetAfterDeletedAccount()

        #expect(model.path.isEmpty)
        #expect(model.subscriptionOutcome == nil)
    }
}
