//
//  SubscriptionStore.swift
//  Twofold
//
//  RevenueCat-backed entitlement state — see `RevenueCatConfig` for SDK bring-up and
//  `PaywallView` for the purchase UI itself. RevenueCatUI's own `PaywallView` component fetches
//  offerings and makes purchases directly against `Purchases.shared`, so this class exists only
//  for the parts of the app that need a live read of "is this user subscribed, and to which
//  tier" without presenting any UI — `RootView`'s app-wide gate, most notably.
//

import Observation
import RevenueCat

enum SubscriptionTier: String, CaseIterable {
    case plus, premium

    var displayName: String {
        switch self {
        case .plus: "Plus"
        case .premium: "Premium"
        }
    }

    /// Matches `profiles.subscription_tier`'s check constraint (`'plus'`/`'premium'`).
    var dbValue: String {
        switch self {
        case .plus: "plus"
        case .premium: "premium"
        }
    }

    /// Shown on the paywall's plan cards, bottom-to-top ("everything in Plus" first for Premium).
    var features: [String] {
        switch self {
        case .plus:
            [
                "Everything you need for long-distance love",
                "Unlimited trips & memories",
                "Track up to 5 flights each month",
                "500+ questions and games",
                "Home Screen & Lock Screen widgets",
            ]
        case .premium:
            [
                "Everything in Twofold Plus",
                "Track up to 20 flights each month",
                "2000+ questions and games",
                "Interactive 3D globe & premium widgets",
                "Relationship Record PDF export",
            ]
        }
    }

    /// The RevenueCat dashboard entitlement identifier backing this tier — see
    /// `RevenueCatConfig.Entitlement`.
    var entitlementIdentifier: String {
        switch self {
        case .plus: RevenueCatConfig.Entitlement.plus
        case .premium: RevenueCatConfig.Entitlement.premium
        }
    }

    /// The higher tier among `customerInfo`'s currently active entitlements, if any. Premium
    /// wins if a customer somehow has both active at once — Plus/Premium share one subscription
    /// group in App Store Connect, so Apple should only ever grant one at a time, but this stays
    /// correct either way, same as the old StoreKit-only version of this check did.
    static func active(in customerInfo: CustomerInfo) -> SubscriptionTier? {
        let active = customerInfo.entitlements.active.keys
        if active.contains(RevenueCatConfig.Entitlement.premium) { return .premium }
        if active.contains(RevenueCatConfig.Entitlement.plus) { return .plus }
        return nil
    }
}

enum BillingPeriod {
    case monthly, yearly
}

@Observable
final class SubscriptionStore {
    var isSubscribed: Bool { subscribedTier != nil }
    private(set) var subscribedTier: SubscriptionTier?

    /// Just the entitlement check — `RootView`'s gate only ever needs this, not a product
    /// catalog fetch, and calling it is cheap: RevenueCat caches `CustomerInfo` locally and only
    /// hits the network when that cache is stale, so this is safe to call on every foreground.
    func refreshEntitlementsOnly() async {
        guard let info = try? await Purchases.shared.customerInfo() else { return }
        subscribedTier = SubscriptionTier.active(in: info)
    }
}
