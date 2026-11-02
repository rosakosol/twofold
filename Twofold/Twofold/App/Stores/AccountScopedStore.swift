//
//  AccountScopedStore.swift
//  Twofold
//
//  A part of `AppModel`'s state that belongs to whoever is signed in.
//

import Foundation

/// A child store of `AppModel` whose state belongs to the signed-in account or its couple.
///
/// `reset()` puts every such property back to what a fresh install has, so the next account to
/// sign in on this device sees none of it. `AppModel.resetAccountScopedState()` calls it on every
/// store in `AppModel.accountScopedStores`, and `AccountScopedStoreTests` fails if a store is
/// added to `AppModel` without being added to that list. So a property added to a store is reset
/// by adding it to that store's `reset()`, which sits next to it.
protocol AccountScopedStore: AnyObject {
    func reset()
}
