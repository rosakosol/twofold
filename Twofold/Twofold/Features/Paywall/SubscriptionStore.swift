//
//  SubscriptionStore.swift
//  Twofold
//
//  RevenueCat-backed entitlement state — see `RevenueCatConfig` for SDK bring-up and
//  `PaywallView` for the purchase UI itself. Owns the full paywall lifecycle: entitlement-only
//  reads for parts of the app that just need "is this user subscribed, and to which tier" without
//  presenting any UI (`RootView`'s app-wide gate, most notably), plus offerings/purchase/restore
//  for `PaywallView`'s own custom-built UI.
//

import Foundation
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

/// One purchasable package, already resolved to which `SubscriptionTier`/`BillingPeriod` it
/// represents — the view layer indexes/iterates over these instead of touching
/// `Offering.availablePackages` or `RevenueCatConfig.ProductIdentifier` directly.
struct PricedPackage: Identifiable {
    let tier: SubscriptionTier
    let period: BillingPeriod
    let package: Package
    var id: String { package.identifier }
}

/// Mutually exclusive by construction (unlike separate `isLoading`/`errorMessage` booleans, which
/// can't stop you from representing "loading and failed at once"). `.idle` only exists for the
/// instant before `PaywallView`'s `.task` fires, so a fresh presentation doesn't flash an error/
/// empty state on first render.
enum PaywallLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

@Observable
final class SubscriptionStore {
    var isSubscribed: Bool { subscribedTier != nil }
    private(set) var subscribedTier: SubscriptionTier?

    private(set) var loadState: PaywallLoadState = .idle
    private(set) var pricedPackages: [PricedPackage] = []

    /// Just the entitlement check — `RootView`'s gate only ever needs this, not a product
    /// catalog fetch, and calling it is cheap: RevenueCat caches `CustomerInfo` locally and only
    /// hits the network when that cache is stale, so this is safe to call on every foreground.
    func refreshEntitlementsOnly() async {
        guard let info = try? await Purchases.shared.customerInfo() else { return }
        subscribedTier = SubscriptionTier.active(in: info)
    }

    func package(for tier: SubscriptionTier, period: BillingPeriod) -> PricedPackage? {
        pricedPackages.first { $0.tier == tier && $0.period == period }
    }

    /// Fetches the RevenueCat dashboard's "current" Offering and resolves its packages into
    /// `pricedPackages` for `PaywallView` to render. Explicit `do/catch` here (unlike the silent
    /// `try?` used for `refreshEntitlementsOnly()`/login/logout elsewhere) since a failure here
    /// needs to show the paywall's own retry state rather than fail invisibly — a paywall that
    /// silently shows nothing on a network hiccup is a real App Store review risk, not just bad UX.
    func loadOfferings() async {
        loadState = .loading
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let current = offerings.current else {
                loadState = .failed("No subscription plans are available right now.")
                return
            }
            let packages = Self.mapToPricedPackages(current.availablePackages)
            guard !packages.isEmpty else {
                loadState = .failed("No subscription plans are available right now.")
                return
            }
            pricedPackages = packages
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Returns `nil` (not a thrown error) when the user cancels the purchase sheet — that's a
    /// normal outcome, not a failure, and the caller shouldn't show an alert for it.
    func purchase(_ pricedPackage: PricedPackage) async throws -> CustomerInfo? {
        let result = try await Purchases.shared.purchase(package: pricedPackage.package)
        guard !result.userCancelled else { return nil }
        subscribedTier = SubscriptionTier.active(in: result.customerInfo)
        return result.customerInfo
    }

    func restore() async throws -> CustomerInfo {
        let info = try await Purchases.shared.restorePurchases()
        subscribedTier = SubscriptionTier.active(in: info)
        return info
    }

    /// Keyed off `RevenueCatConfig.ProductIdentifier` — the only signal that distinguishes Plus
    /// from Premium, since RevenueCat's own `Package.packageType` (`.monthly`/`.annual`/...) can't:
    /// both tiers have a monthly and an annual variant. A package whose product identifier or
    /// billing period this app doesn't recognize is dropped rather than shown or force-unwrapped —
    /// a dashboard/App-Store-Connect mismatch should make that one package quietly disappear from
    /// the paywall, not take the whole screen down.
    private static func mapToPricedPackages(_ packages: [Package]) -> [PricedPackage] {
        packages.compactMap { package in
            guard let tier = tier(forProductIdentifier: package.storeProduct.productIdentifier),
                  let period = billingPeriod(for: package.storeProduct.subscriptionPeriod) else { return nil }
            return PricedPackage(tier: tier, period: period, package: package)
        }
    }

    private static func tier(forProductIdentifier id: String) -> SubscriptionTier? {
        switch id {
        case RevenueCatConfig.ProductIdentifier.monthlyPlus, RevenueCatConfig.ProductIdentifier.yearlyPlus:
            return .plus
        case RevenueCatConfig.ProductIdentifier.monthlyPremium, RevenueCatConfig.ProductIdentifier.yearlyPremium:
            return .premium
        default:
            return nil
        }
    }

    private static func billingPeriod(for period: SubscriptionPeriod?) -> BillingPeriod? {
        switch period?.unit {
        case .month: .monthly
        case .year: .yearly
        default: nil
        }
    }
}
