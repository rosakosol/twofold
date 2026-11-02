//
//  AccountScopedStoreTests.swift
//  TwofoldTests
//
//  Sign-out resets every child store `AppModel` owns, including one added later.
//
//  `resetAccountScopedState()` resets the stores in `AppModel.accountScopedStores`. That list is
//  written by hand, so this reads `AppModel`'s own stored properties and fails for any store found
//  there that the list leaves out: a store added without being listed would otherwise keep its
//  state across a sign-out, which is the leak `AccountScopedStateResetTests` was written about.
//

import Foundation
import Testing
@testable import Twofold

@Suite("Every child store is reset on sign-out")
@MainActor
struct AccountScopedStoreTests {

    /// Every stored property of `model` that is an account-scoped store, by name.
    private func storedStores(of model: AppModel) -> [(name: String, store: any AccountScopedStore)] {
        Mirror(reflecting: model).children.compactMap { child in
            guard let store = child.value as? any AccountScopedStore else { return nil }
            return (child.label ?? "?", store)
        }
    }

    @Test("Every store AppModel holds is one resetAccountScopedState resets")
    func everyStoreIsListed() {
        let model = AppModel()
        let listed = Set(model.accountScopedStores.map { ObjectIdentifier($0) })
        let found = storedStores(of: model)

        #expect(!found.isEmpty)
        for (name, store) in found {
            #expect(listed.contains(ObjectIdentifier(store)), "\(name) is not in accountScopedStores, so sign-out would not reset it")
        }
        #expect(found.count == model.accountScopedStores.count)
    }
}

extension PendingMemoryDiskTests {
    /// Nested here because signing out clears the stores on disk the suites here also use.
    @Suite("Signing out resets every child store", .serialized)
    @MainActor
    struct SignOutResetsEveryStoreTests {

        @Test("After sign-out, every store holds what a fresh one does")
        func signOutResetsEveryStore() async {
            let model = AppModel()
            model.sessionTeardown = FakeSessionTeardown()
            model.session.hasCouple = true
            model.session.partnerConnected = true
            model.session.backendCoupleID = UUID()
            model.session.hasResolvedOutgoingConnectionRequest = true
            model.subscription.apply(active: true, viewerHolds: true, tier: "premium", viewerStore: "stripe")
            model.prompts.writeRefusedMessage = "refused"
            model.prompts.setupChecklistDismissed = true
            model.games.applyDemoState()
            model.games.isDailyQuestionOpenRequested = true
            model.travel.trips = DemoData.trips
            model.travel.flights = DemoData.flights
            model.myDrawingURL = URL(string: "https://example.test/pad.png")

            await model.signOut()

            #expect(model.session.hasCouple == false)
            #expect(model.session.partnerConnected == false)
            #expect(model.session.backendCoupleID == nil)
            #expect(model.session.hasResolvedOutgoingConnectionRequest == false)
            #expect(model.subscription.isActive == false)
            #expect(model.subscription.viewerHoldsSubscription == false)
            #expect(model.subscription.tier == nil)
            #expect(model.prompts.writeRefusedMessage == nil)
            #expect(model.prompts.setupChecklistDismissed == false)
            #expect(model.games.dailyStreak == nil)
            #expect(model.games.gameDecks == nil)
            #expect(model.games.isDailyQuestionOpenRequested == false)
            #expect(model.travel.trips.isEmpty)
            #expect(model.travel.flights.isEmpty)
            #expect(model.myDrawingURL == nil)
        }
    }
}
