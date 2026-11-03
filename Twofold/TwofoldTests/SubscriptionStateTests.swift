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
        state.isActive = true
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

    /// The owner's rule: Premium is what a couple is paying for now, not what they once paid for.
    /// `tier` outlives a lapse (the refresh that learns of one leaves it alone, the webhook may too,
    /// and the solo path reads the raw column), so every Premium gate has to ask `isActive` as well.
    @Test("A lapsed Premium couple is locked out of Premium features, whatever the leftover tier says")
    func lapsedPremiumIsLocked() {
        let state = SubscriptionState()
        state.apply(active: false, viewerHolds: false, tier: "premium", viewerStore: nil)
        #expect(state.isPremiumLocked)
        #expect(state.isDeckLocked(Self.deck(tier: "premium")))
        // Plus decks are free to every couple — the lapse takes away Premium, not the rest.
        #expect(!state.isDeckLocked(Self.deck(tier: "plus")))
    }

    @Test("A foreground refresh that learns of a lapse locks Premium again")
    func refreshThatLapsesLocks() {
        let state = SubscriptionState()
        state.apply(active: true, viewerHolds: false, tier: "premium", viewerStore: nil)
        #expect(!state.isPremiumLocked)
        // What `RootView.checkSubscription` does: the snapshot carries no tier, so `tier` is left
        // as it was and only `isActive` changes.
        state.applyRefresh(.init(active: false, sawActiveCouple: true, tier: nil), deviceEntitled: false, partnerConnected: true)
        #expect(state.tier == "premium")
        #expect(state.isPremiumLocked)
        #expect(state.isDeckLocked(Self.deck(tier: "premium")))
        // And resubscribing gives it straight back.
        state.markActive(tier: "premium")
        #expect(!state.isPremiumLocked)
    }

    @Test("The tier a couple is entitled to is nil once they have lapsed")
    func entitledTier() {
        let state = SubscriptionState()
        state.apply(active: true, viewerHolds: true, tier: "premium", viewerStore: nil)
        #expect(state.entitledTier == "premium")
        state.isActive = false
        #expect(state.entitledTier == nil)
        #expect(!LocalGameSessionStore.canStart(deck: Self.deck(tier: "premium"), effectiveTier: state.entitledTier, hasPartner: true))
    }

    private static func deck(tier: String) -> GameDeck {
        GameDeck(id: UUID(), topic: "Travel", gameType: .triviaBattle, title: "Airport Chaos", emoji: "🛫", tier: tier, sortOrder: 0, questionCount: 10)
    }

    @Test("AppModel reads and writes through to it")
    func appModelForwards() {
        let model = AppModel()
        model.subscription.isActive = true
        model.subscription.tier = "premium"
        #expect(model.subscription.isActive)
        #expect(model.subscription.tier == "premium")
        #expect(!model.subscription.isPremiumLocked)
    }
}

@Suite("The couple's subscription, read once")
@MainActor
struct SubscriptionSnapshotTests {

    @Test("Premium wins when either active partner has it")
    func premiumWins() {
        #expect(BackendService.effectiveTier([(true, "plus"), (true, "premium")]) == "premium")
        #expect(BackendService.effectiveTier([(true, "premium"), (true, "plus")]) == "premium")
    }

    @Test("A lapsed partner's leftover tier does not count")
    func lapsedTierIgnored() {
        #expect(BackendService.effectiveTier([(false, "premium"), (true, "plus")]) == "plus")
        #expect(BackendService.effectiveTier([(false, "premium"), (false, "plus")]) == nil)
    }

    @Test("An active subscriber from before the tier column has no tier")
    func noTier() {
        #expect(BackendService.effectiveTier([(true, nil)]) == nil)
        #expect(BackendService.effectiveTier([]) == nil)
    }

    @Test("A false that could not see the couple is not trusted while a partner is connected")
    func falseWithoutCoupleIgnored() {
        let state = SubscriptionState()
        state.isActive = true
        state.applyRefresh(.init(active: false, sawActiveCouple: false, tier: nil), deviceEntitled: false, partnerConnected: true)
        #expect(state.isActive)
        state.applyRefresh(.init(active: false, sawActiveCouple: true, tier: nil), deviceEntitled: false, partnerConnected: true)
        #expect(!state.isActive)
    }

    @Test("A backend false is overruled by this device's own entitlement")
    func deviceEntitlementWins() {
        let state = SubscriptionState()
        state.applyRefresh(.init(active: false, sawActiveCouple: false, tier: nil), deviceEntitled: true, partnerConnected: false)
        #expect(state.isActive)
    }
}

@Suite("Leaks reset() used to leave behind (CORE-5)")
@MainActor
struct AccountScopedLeakTests {

    @Test("Whether this person pays goes, so the next account is not told to cancel it")
    func viewerHoldsSubscriptionIsCleared() {
        let state = SubscriptionState()
        state.apply(active: true, viewerHolds: true, tier: "plus", viewerStore: "app_store")
        state.reset()
        #expect(state.viewerHoldsSubscription == false)
    }

    @Test("The outgoing request lookup counts as not asked yet, for the next account")
    func outgoingRequestResolutionIsCleared() async {
        let session = CoupleSession()
        session.hasResolvedOutgoingConnectionRequest = true
        session.reset()
        #expect(session.hasResolvedOutgoingConnectionRequest == false)
    }

    @Test("The decks' unavailable state and a pending open of today's question go")
    func gamesFlagsAreCleared() {
        let games = GamesState()
        games.applyDemoState()
        games.isDailyQuestionOpenRequested = true
        games.markDecksUnavailableForTesting()
        games.reset()
        #expect(games.gameDecksUnavailable == false)
        #expect(games.isDailyQuestionOpenRequested == false)
    }
}
