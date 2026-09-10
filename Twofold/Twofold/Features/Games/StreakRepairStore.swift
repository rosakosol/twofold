//
//  StreakRepairStore.swift
//  Twofold
//
//  Buying and spending a streak repair.
//
//  The one thing that makes this different from every other purchase in the app: a repair is not
//  granted by the purchase. Apple confirms it, RevenueCat sends a NON_RENEWING_PURCHASE webhook,
//  and only then does a credit exist for `repair_couple_streak` to spend. That round trip is
//  usually a second or two and occasionally longer, so between the sheet dismissing and the credit
//  landing there is a window where the person has paid and the server will still say no.
//
//  Hence the retry below. It is not defensive coding around a flaky call — `no_credit` immediately
//  after a successful purchase is the expected reading, not an error, and showing it as one would
//  tell someone their payment failed when it did not.
//

import Foundation
import RevenueCat

@MainActor
@Observable
final class StreakRepairStore {

    enum Phase: Equatable {
        case idle
        case loadingPrice
        case purchasing
        /// Paid; waiting for the webhook to grant the credit.
        case confirming
        case repaired(streak: Int)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Localised by the store, so it reads $0.99 or $1.99 or ¥160 wherever the buyer is. Never
    /// hard-coded — a price written into the app is wrong in most of the world.
    private(set) var displayPrice: String?

    private var product: StoreProduct?

    /// How long to keep asking after a successful purchase before giving up on the webhook.
    ///
    /// Twelve seconds is chosen to be longer than a webhook normally takes and shorter than
    /// someone will hold a phone waiting. Giving up is not losing the credit: it stays on the
    /// account, and the next attempt spends it.
    private static let confirmationWindow: TimeInterval = 12
    private static let pollInterval: Duration = .milliseconds(750)

    func loadPrice() async {
        guard product == nil else { return }
        phase = .loadingPrice
        let products = await Purchases.shared.products([RevenueCatConfig.ProductIdentifier.streakRepair])
        product = products.first
        displayPrice = products.first?.localizedPriceString
        phase = .idle
    }

    /// Buys a repair and spends it. Returns true if the streak came back.
    ///
    /// Deliberately one call rather than two. Someone tapping "Repair my streak" is asking for
    /// their streak, not for a credit — a flow that ends with "purchased!" and leaves them to find
    /// a second button would be a worse version of the same thing.
    @discardableResult
    func purchaseAndRepair() async -> Bool {
        if product == nil { await loadPrice() }
        guard let product else {
            phase = .failed("That's not available right now. Try again in a moment.")
            return false
        }

        phase = .purchasing
        do {
            let result = try await Purchases.shared.purchase(product: product)
            if result.userCancelled {
                phase = .idle
                return false
            }
        } catch {
            phase = .failed(error.localizedDescription)
            return false
        }

        phase = .confirming
        return await spendCredit()
    }

    /// Spends a credit that may not have arrived yet, retrying until it does.
    ///
    /// Also the path for someone who paid, closed the app, and came back — they hold a credit and
    /// have nothing to buy, so this is called on its own.
    @discardableResult
    func spendCredit() async -> Bool {
        let deadline = Date().addingTimeInterval(Self.confirmationWindow)

        while true {
            do {
                switch try await BackendService.repairCoupleStreak() {
                case .repaired(let streak):
                    phase = .repaired(streak: streak)
                    return true
                case .refused(let message):
                    phase = .failed(message)
                    return false
                case .noCredit:
                    guard Date() < deadline else {
                        // Paid, and the credit has not arrived. Said plainly rather than as a
                        // failure, because nothing has been lost — it will be there shortly, and
                        // the next attempt will spend it.
                        phase = .failed("Your purchase went through — we're still waiting on it. Try again in a moment and your streak will come back.")
                        return false
                    }
                }
            } catch {
                phase = .failed("Couldn't reach Twofold. Check your connection and try again.")
                return false
            }
            try? await Task.sleep(for: Self.pollInterval)
        }
    }
}
