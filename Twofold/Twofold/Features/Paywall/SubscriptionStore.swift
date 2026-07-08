//
//  SubscriptionStore.swift
//  Twofold
//
//  Stand-in for StoreKit 2. Real purchases require a `.storekit` configuration
//  file and product identifiers set up in Xcode (App > Signing & Capabilities
//  > In-App Purchase, plus a StoreKit Configuration file for local testing)
//  before `Product.products(for:)` / `product.purchase()` can be wired in here.
//

import Observation

@Observable
final class SubscriptionStore {
    var selectedTier: SubscriptionTier = .plus
    var isPurchasing = false
    var currentTier: SubscriptionTier = .free

    func purchase(_ tier: SubscriptionTier) async {
        isPurchasing = true
        defer { isPurchasing = false }
        try? await Task.sleep(for: .seconds(1))
        currentTier = tier
    }
}
