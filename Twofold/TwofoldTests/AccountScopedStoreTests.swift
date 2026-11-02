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
