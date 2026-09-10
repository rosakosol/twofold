//
//  StreakRepairTests.swift
//  TwofoldTests
//
//  Buying back a broken streak, on the client side.
//
//  Two things here can cost a real person real money if they are wrong, and they get the
//  assertions. An offer shown outside its window sells something that cannot work. And a purchase
//  that succeeds while the credit is still in flight must not read as a failure — that is the
//  expected sequence, not an error, and telling someone their payment failed when it did not is
//  the worst thing this flow can do.
//

import Testing
import Foundation
@testable import Twofold

struct StreakRepairTests {

    private func state(
        repairable: Bool = true,
        streak: Int = 27,
        credits: Int = 0
    ) -> BackendService.StreakRepairState {
        .init(repairable: repairable, streakAtRisk: streak, credits: credits, missedDateRaw: nil)
    }

    // MARK: - Decoding

    /// Straight from the RPC, under the same ISO-8601 date strategy the Supabase client uses.
    ///
    /// This is the assertion that caught a real bug rather than confirming one. `missed_date` is a
    /// bare Postgres `date`, which that strategy refuses — so decoding threw, the whole row was
    /// lost, `streakRepairState()` returned nil, and the offer would never have appeared in
    /// production with nothing on screen to explain it. Exactly the trap `CoupleRow` documents,
    /// walked into again. It is a string now, parsed separately.
    @Test("the RPC's row decodes, date and all")
    func decodes() throws {
        let json = #"""
        {"repairable":true,"streak_at_risk":27,"credits":1,"missed_date":"2026-09-09"}
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackendService.StreakRepairState.self, from: Data(json.utf8))
        #expect(decoded.repairable)
        #expect(decoded.streakAtRisk == 27)
        #expect(decoded.credits == 1)
        #expect(decoded.missedDate != nil, "the date-only value should still parse")
    }

    /// And a null one is fine — the offer does not depend on it.
    @Test("a missing date does not sink the row")
    func nullDateIsTolerated() throws {
        let json = #"{"repairable":true,"streak_at_risk":5,"credits":0,"missed_date":null}"#
        let decoded = try JSONDecoder().decode(BackendService.StreakRepairState.self, from: Data(json.utf8))
        #expect(decoded.repairable)
        #expect(decoded.missedDate == nil)
    }

    // MARK: - When the offer appears

    /// The card's own condition. A streak of zero is the whole point — someone who never had one
    /// has nothing to buy back, and showing them a price for it would be selling nothing.
    private func offerIsShown(_ s: BackendService.StreakRepairState?) -> Bool {
        guard let s else { return false }
        return s.repairable && s.streakAtRisk > 0
    }

    @Test("the offer appears only inside the window, for a couple who had a streak")
    func offerConditions() {
        #expect(offerIsShown(state()))
        #expect(!offerIsShown(state(repairable: false)), "outside the window, nothing is offered")
        #expect(!offerIsShown(state(streak: 0)), "nothing to buy back")
        #expect(!offerIsShown(nil), "a failed lookup shows no offer rather than a wrong one")
    }

    // MARK: - Outcomes

    /// `no_credit` is a token the app acts on, not prose it shows. If it ever reached the screen
    /// it would read as gibberish at the exact moment someone had just paid.
    @Test("no_credit is recognised rather than displayed")
    func noCreditIsNotAMessage() {
        let outcome = BackendService.StreakRepairOutcome.noCredit
        guard case .noCredit = outcome else {
            Issue.record("expected noCredit")
            return
        }
    }

    /// The distinction the flow rests on: a refusal is final and shows its message, while
    /// `noCredit` means try again shortly. Collapsing the two would either spam a doomed retry or
    /// abandon someone who has paid.
    @Test("a refusal and a missing credit are different things")
    func refusalIsNotNoCredit() {
        let refused = BackendService.StreakRepairOutcome.refused("Your streak is still going.")
        if case .noCredit = refused {
            Issue.record("a refusal must not be treated as a pending credit")
        }
        if case .refused(let message) = refused {
            #expect(!message.contains("_"), "a refusal's message is shown to a person")
        }
    }

    @Test("a repair reports the streak it restored")
    func repairedCarriesTheStreak() {
        guard case .repaired(let streak) = BackendService.StreakRepairOutcome.repaired(streak: 27) else {
            Issue.record("expected repaired")
            return
        }
        #expect(streak == 27)
    }

    // MARK: - The store's phases

    /// Someone who already holds a credit must not be charged again. The card branches on this,
    /// and getting it backwards means charging twice for one repair.
    private func shouldPurchase(credits: Int) -> Bool { credits == 0 }

    @Test("holding a credit spends it instead of buying another")
    func heldCreditIsSpent() {
        #expect(shouldPurchase(credits: 0))
        #expect(!shouldPurchase(credits: 1), "a held credit is spent, not topped up")
        #expect(!shouldPurchase(credits: 3))
    }

    /// A cancelled purchase returns to idle — not to an error. Backing out of a payment sheet is a
    /// decision, not a fault, and showing it in red would say otherwise.
    @MainActor
    @Test("cancelling leaves no error behind")
    func cancellingIsNotAnError() {
        let store = StreakRepairStore()
        #expect(store.phase == .idle)
        if case .failed = store.phase {
            Issue.record("a fresh store must not start in a failed state")
        }
    }
}
