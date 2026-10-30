//
//  FreeTrialEligibilityTests.swift
//  TwofoldTests
//
//  Trial copy only for a trial this Apple Account will actually get.
//
//  The paywall said "Start my 14-day free trial" to everyone, the trial screen promised "Day 14",
//  and the success screen said a trial had started even after a restore. Apple gives one intro
//  offer per subscription group per Apple Account, and only Plus has a trial at all, so lapsed
//  subscribers and anyone choosing Premium were promised free days and charged. The length now
//  comes from the product's offer and the promise from an eligibility check, behind a seam this
//  file fakes.
//

import Foundation
import Testing
@testable import Twofold

/// Answers eligibility from a fixed table, and records what it was asked.
@MainActor
private final class FakeEligibilityChecker: IntroOfferEligibilityChecking {
    var answers: [String: IntroOfferEligibility]
    private(set) var askedAbout: [String] = []

    init(_ answers: [String: IntroOfferEligibility]) {
        self.answers = answers
    }

    func eligibility(forProductIdentifiers productIdentifiers: [String]) async -> [String: IntroOfferEligibility] {
        askedAbout += productIdentifiers
        return answers.filter { productIdentifiers.contains($0.key) }
    }
}

@Suite("Free-trial copy follows eligibility")
@MainActor
struct FreeTrialEligibilityTests {

    private let twoWeekTrial = IntroductoryOfferTerms(isFreeTrial: true, periodValue: 2, periodUnit: .week)

    // MARK: - Joining offer and eligibility

    @Test("an eligible two-week trial reads as 14 days")
    func eligibleTwoWeeks() {
        let trial = FreeTrialOffer.resolve(terms: twoWeekTrial, eligibility: .eligible)
        #expect(trial?.lengthAdjective == "14-day")
        #expect(trial?.duration == "14 days")
        #expect(trial?.dayCount == 14)
    }

    @Test("no trial unless eligibility is a plain yes", arguments: [
        IntroOfferEligibility?.some(.ineligible),
        IntroOfferEligibility?.some(.unknown),
        IntroOfferEligibility?.none,
    ])
    func notEligibleMeansNoTrial(eligibility: IntroOfferEligibility?) {
        #expect(FreeTrialOffer.resolve(terms: twoWeekTrial, eligibility: eligibility) == nil)
    }

    @Test("a product with no intro offer, or a paid one, has no free trial")
    func noOfferOrPaidOffer() {
        #expect(FreeTrialOffer.resolve(terms: nil, eligibility: .eligible) == nil)
        let discount = IntroductoryOfferTerms(isFreeTrial: false, periodValue: 1, periodUnit: .month)
        #expect(FreeTrialOffer.resolve(terms: discount, eligibility: .eligible) == nil)
    }

    @Test("the length comes from the offer, in its own unit")
    func lengthFromOffer() {
        let week = FreeTrialOffer.resolve(terms: .init(isFreeTrial: true, periodValue: 1, periodUnit: .week), eligibility: .eligible)
        #expect(week?.lengthAdjective == "7-day")
        let month = FreeTrialOffer.resolve(terms: .init(isFreeTrial: true, periodValue: 1, periodUnit: .month), eligibility: .eligible)
        #expect(month?.lengthAdjective == "1-month")
        #expect(month?.duration == "1 month")
        #expect(month?.dayCount == nil)
        let threeDays = FreeTrialOffer.resolve(terms: .init(isFreeTrial: true, periodValue: 3, periodUnit: .day), eligibility: .eligible)
        #expect(threeDays?.duration == "3 days")
    }

    // MARK: - Through the store, with a fake checker

    @Test("the store keeps a trial only for eligible products that have one")
    func storeResolvesPerProduct() async {
        let checker = FakeEligibilityChecker([
            "plus.yearly": .eligible,
            "plus.monthly": .ineligible,
        ])
        let store = SubscriptionStore(introEligibility: checker)

        await store.resolveFreeTrials([
            "plus.yearly": twoWeekTrial,
            "plus.monthly": twoWeekTrial,
            "premium.yearly": IntroductoryOfferTerms(isFreeTrial: false, periodValue: 1, periodUnit: .month),
        ])

        #expect(store.freeTrials["plus.yearly"]?.lengthAdjective == "14-day")
        #expect(store.freeTrials["plus.monthly"] == nil)
        #expect(store.freeTrials["premium.yearly"] == nil)
        // A paid intro offer is not a trial, so there was nothing to ask about.
        #expect(!checker.askedAbout.contains("premium.yearly"))
    }

    @Test("an unanswered eligibility check leaves no trial copy")
    func unknownIsNoTrial() async {
        let store = SubscriptionStore(introEligibility: FakeEligibilityChecker([:]))
        await store.resolveFreeTrials(["plus.yearly": twoWeekTrial])
        #expect(store.freeTrials.isEmpty)
    }

    // MARK: - Copy

    @Test("the paywall button and caption mention a trial only when there is one")
    func paywallCopy() {
        let trial = FreeTrialOffer.resolve(terms: twoWeekTrial, eligibility: .eligible)
        #expect(PaywallTrialCopy.primaryTitle(trial: trial) == "Start my 14-day free trial")
        #expect(PaywallTrialCopy.caption(trial: trial, localizedPrice: "$49.99", periodLabel: "year") == "14 days free, then $49.99 a year")

        #expect(PaywallTrialCopy.primaryTitle(trial: nil) == "Subscribe")
        let plain = PaywallTrialCopy.caption(trial: nil, localizedPrice: "$49.99", periodLabel: "year")
        #expect(plain.contains("$49.99 a year"))
        #expect(!plain.localizedCaseInsensitiveContains("free"))
        #expect(!plain.localizedCaseInsensitiveContains("trial"))
    }

    @Test("the trial screen's timeline follows the real length, and drops the trial without one")
    func trialTimeline() {
        let trial = FreeTrialOffer.resolve(terms: twoWeekTrial, eligibility: .eligible)
        #expect(TrialTrustView.timeline(for: trial).map(\.label) == ["Today", "Day 12", "Day 14"])

        let week = FreeTrialOffer.resolve(terms: .init(isFreeTrial: true, periodValue: 1, periodUnit: .week), eligibility: .eligible)
        #expect(TrialTrustView.timeline(for: week).map(\.label) == ["Today", "Day 5", "Day 7"])

        let none = TrialTrustView.timeline(for: nil)
        #expect(none.allSatisfy { !$0.title.localizedCaseInsensitiveContains("trial") })
        #expect(none.allSatisfy { !$0.label.hasPrefix("Day") })
    }

    @Test("the success screen says a trial started only when one did")
    func successSubtitle() {
        let started = SubscriptionOutcome.afterPurchase(entitlementIsInTrial: true, terms: twoWeekTrial)
        #expect(started.successSubtitle == "Your 14-day free trial has started.")

        let paid = SubscriptionOutcome.afterPurchase(entitlementIsInTrial: false, terms: twoWeekTrial)
        #expect(!paid.successSubtitle.localizedCaseInsensitiveContains("trial"))

        #expect(!SubscriptionOutcome.restored.successSubtitle.localizedCaseInsensitiveContains("trial"))
    }
}
