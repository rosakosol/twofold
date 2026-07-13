//
//  SubscriptionStore.swift
//  Twofold
//
//  Real StoreKit 2. For local/Simulator testing, create a `.storekit` configuration file in
//  Xcode (File > New > File > StoreKit Configuration File) with subscription products matching
//  the IDs below, then set it in Product > Scheme > Edit Scheme > Run > Options > StoreKit
//  Configuration — that's what makes `Product.products(for:)` return real data when run from
//  Xcode. (`SKTestSession` looked like an alternative that would work regardless of how the app
//  was launched, but it turns out to require an actual XCTest host process — calling it from
//  regular app code crashes immediately, so that's not an option here.) The real products still
//  need creating in App Store Connect with final pricing before this ships.
//

import Observation
import StoreKit

enum SubscriptionTier: CaseIterable {
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
}

enum BillingPeriod {
    case monthly, yearly
}

@Observable
final class SubscriptionStore {
    private static func productID(tier: SubscriptionTier, period: BillingPeriod) -> String {
        switch (tier, period) {
        case (.plus, .monthly): "com.orangefinch.Twofold.plus.monthly"
        case (.plus, .yearly): "com.orangefinch.Twofold.plus.yearly"
        case (.premium, .monthly): "com.orangefinch.Twofold.premium.monthly"
        case (.premium, .yearly): "com.orangefinch.Twofold.premium.yearly"
        }
    }

    private static var allProductIDs: [String] {
        SubscriptionTier.allCases.flatMap { tier in
            [BillingPeriod.monthly, .yearly].map { productID(tier: tier, period: $0) }
        }
    }

    var products: [Product] = []
    var isLoadingProducts = false
    var isPurchasing = false
    var purchaseError: String?
    private var purchasedProductIDs: Set<String> = []

    private var updatesTask: Task<Void, Never>?

    var isSubscribed: Bool { !purchasedProductIDs.isEmpty }

    /// The highest tier among the caller's current entitlements, if any — used to persist which
    /// tier was purchased/restored (`updateSubscriptionStatus`'s `tier` param). Premium wins if
    /// `purchasedProductIDs` somehow contains both (Plus/Premium are the same subscription
    /// group, so Apple should only ever return one active entitlement, but this stays correct
    /// either way).
    var subscribedTier: SubscriptionTier? {
        if purchasedProductIDs.contains(where: { $0.contains("premium") }) { return .premium }
        if purchasedProductIDs.contains(where: { $0.contains("plus") }) { return .plus }
        return nil
    }

    func product(tier: SubscriptionTier, period: BillingPeriod) -> Product? {
        products.first { $0.id == Self.productID(tier: tier, period: period) }
    }

    /// The discount of the yearly plan vs. paying monthly for a year, e.g. `50` for 50% off.
    /// `nil` if either product hasn't loaded yet, or there's genuinely no discount to show.
    func yearlyDiscountPercent(tier: SubscriptionTier) -> Int? {
        guard let monthly = product(tier: tier, period: .monthly),
              let yearly = product(tier: tier, period: .yearly),
              monthly.price > 0 else { return nil }
        let annualizedMonthly = monthly.price * 12
        let discount = (annualizedMonthly - yearly.price) / annualizedMonthly
        let percent = NSDecimalNumber(decimal: discount * 100).intValue
        return percent > 0 ? percent : nil
    }

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: Self.allProductIDs)
            // Xcode's local StoreKit testing config has a known flakiness where a product's
            // `price` isn't always fully hydrated on the very first `Product.products(for:)`
            // call of a session (all IDs come back, but one's price reads as 0 momentarily) —
            // since this only ever ran once with no retry, a single bad snapshot silently
            // suppressed the yearly-discount badge (and anything else gated on price > 0) for
            // the rest of the session. One short retry clears it up without adding a visible
            // delay for the common case where everything's fine the first time.
            if products.contains(where: { $0.price <= 0 }) {
                try? await Task.sleep(for: .milliseconds(400))
                products = try await Product.products(for: Self.allProductIDs)
            }
        } catch {
            purchaseError = error.localizedDescription
        }
        await refreshEntitlements()
    }

    /// Just the entitlement check, without the product/pricing catalog fetch — for callers
    /// that only need `isSubscribed` (e.g. `RootView`'s gate check). Calling the full
    /// `loadProducts()` from two places at once (this store's own instance *and*
    /// `PaywallView`'s separate instance, both firing around cold launch) was hammering the
    /// local StoreKit test session with two concurrent `Product.products(for:)` catalog
    /// fetches for the same IDs, which is what broke `PaywallView`'s own product loading.
    func refreshEntitlementsOnly() async {
        await refreshEntitlements()
    }

    /// Returns `true` on a completed (verified) purchase. `false` covers both user
    /// cancellation and a pending purchase (e.g. requires parental approval) — neither is
    /// an error, so `purchaseError` is only set for genuine failures.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verification.payloadValue
                purchasedProductIDs.insert(transaction.productID)
                await transaction.finish()
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func refreshEntitlements() async {
        var ids: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if let transaction = try? result.payloadValue {
                ids.insert(transaction.productID)
            }
        }
        purchasedProductIDs = ids
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard let transaction = try? update.payloadValue else { return }
        purchasedProductIDs.insert(transaction.productID)
        await transaction.finish()
    }
}

extension Product.SubscriptionPeriod {
    var displayLabel: String {
        switch unit {
        case .day: value == 1 ? "day" : "\(value) days"
        case .week: value == 1 ? "week" : "\(value) weeks"
        case .month: value == 1 ? "month" : "\(value) months"
        case .year: value == 1 ? "year" : "\(value) years"
        @unknown default: ""
        }
    }
}
