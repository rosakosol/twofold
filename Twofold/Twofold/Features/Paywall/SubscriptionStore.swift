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

@Observable
final class SubscriptionStore {
    static let monthlyProductID = "com.orangefinch.Twofold.plus.monthly"
    static let yearlyProductID = "com.orangefinch.Twofold.plus.yearly"

    var products: [Product] = []
    var isLoadingProducts = false
    var isPurchasing = false
    var purchaseError: String?
    private var purchasedProductIDs: Set<String> = []

    private var updatesTask: Task<Void, Never>?

    var isSubscribed: Bool { !purchasedProductIDs.isEmpty }
    var monthlyProduct: Product? { products.first { $0.id == Self.monthlyProductID } }
    var yearlyProduct: Product? { products.first { $0.id == Self.yearlyProductID } }

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
            products = try await Product.products(for: [Self.monthlyProductID, Self.yearlyProductID])
        } catch {
            purchaseError = error.localizedDescription
        }
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
