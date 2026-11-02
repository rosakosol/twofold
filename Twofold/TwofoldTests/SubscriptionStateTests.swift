//
//  SubscriptionStateTests.swift
//  TwofoldTests
//
//  What the subscription store holds, and that reset() leaves none of it for the next account.
//

import Foundation
import Testing
@testable import Twofold

@Suite("SubscriptionState")
@MainActor
struct SubscriptionStateTests {

    private func dirtied() -> SubscriptionState {
        let state = SubscriptionState()
        state.apply(active: true, viewerHolds: true, tier: "premium", viewerStore: "rc_billing")
        return state
    }

    @Test("reset() forgets whether anyone pays, the tier, and where it was bought")
    func resetClearsEverything() {
        let state = dirtied()
        state.reset()

        #expect(state.isActive == false)
        #expect(state.hasResolved == false)
        #expect(state.tier == nil)
        #expect(state.viewerStore == nil)
    }

    @Test("An adopt's answer counts as resolved")
    func applyResolves() {
        let state = SubscriptionState()
        #expect(state.hasResolved == false)
        state.apply(active: false, viewerHolds: false, tier: nil, viewerStore: nil)
        #expect(state.hasResolved)
    }

    @Test("Premium unlocks premium decks and features; anything else does not")
    func gates() {
        let state = SubscriptionState()
        state.tier = "plus"
        #expect(state.isPremiumLocked)
        state.tier = "premium"
        #expect(!state.isPremiumLocked)
        state.isActive = false
        #expect(!state.canAddContent)
        state.markActive(tier: "plus")
        #expect(state.canAddContent)
        #expect(state.tier == "plus")
    }

    @Test("AppModel reads and writes through to it")
    func appModelForwards() {
        let model = AppModel()
        model.isSubscriptionActive = true
        model.subscriptionTier = "premium"
        #expect(model.subscription.isActive)
        #expect(model.subscription.tier == "premium")
        #expect(!model.isPremiumLocked)
    }
}
