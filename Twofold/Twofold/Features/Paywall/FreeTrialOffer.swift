//
//  FreeTrialOffer.swift
//  Twofold
//
//  Whether this Apple Account will actually get a free trial on a product, and how long it is.
//
//  The paywall used to say "Start my 14-day free trial" to everyone. Apple decides who gets an
//  introductory offer: one per subscription group per Apple Account, so somebody who lapsed, or
//  who already had the trial under another Twofold account, is charged on the day they tap a
//  button that promised fourteen free ones. That is App Review guideline 3.1.2 territory. The
//  length was hard-coded too, and only Plus has a trial at all (see Twofold.storekit), so the
//  same words sat over Premium, which has none.
//
//  So trial copy now needs two things: the product's own introductory offer, which is a free
//  trial and gives the length, and RevenueCat's eligibility answer for this Apple Account. If
//  either is missing, or the answer is "unknown", the screens say nothing about a trial. Not
//  promising one costs nothing. Promising one that is not there costs a charge nobody expected.
//

import Foundation
import RevenueCat

/// RevenueCat's `IntroEligibilityStatus`, collapsed to the one question the copy asks. Its own
/// type so tests can hand one in; RevenueCat's `IntroEligibility` has no public initialiser.
enum IntroOfferEligibility: Equatable {
    case eligible
    case ineligible
    /// Not enough information to say: no receipt yet, a network failure, or an SDK that is not
    /// configured. Treated exactly like `.ineligible` by the copy.
    case unknown
}

/// The seam between the paywall and RevenueCat's eligibility check, so the copy can be tested
/// against a fake instead of the App Store.
protocol IntroOfferEligibilityChecking {
    func eligibility(forProductIdentifiers productIdentifiers: [String]) async -> [String: IntroOfferEligibility]
}

/// The real one. RevenueCat answers from StoreKit 2's `isEligibleForIntroOffer` where it can,
/// which is the check Apple applies when the purchase goes through.
struct RevenueCatIntroOfferEligibilityChecker: IntroOfferEligibilityChecking {
    func eligibility(forProductIdentifiers productIdentifiers: [String]) async -> [String: IntroOfferEligibility] {
        let answers = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: productIdentifiers)
        return answers.mapValues { answer in
            switch answer.status {
            case .eligible: .eligible
            // No intro offer means no trial to be eligible for, which comes to the same thing.
            case .ineligible, .noIntroOfferExists: .ineligible
            case .unknown: .unknown
            @unknown default: .unknown
            }
        }
    }
}

/// A product's introductory offer as the App Store describes it, with nothing from RevenueCat's
/// types, so tests can build one.
struct IntroductoryOfferTerms: Equatable {
    enum Unit: Equatable {
        case day, week, month, year
    }

    /// Only a free trial counts. Pay-as-you-go and pay-up-front intro prices are discounts, and
    /// calling either one "free" would be the same misstatement this file exists to stop.
    let isFreeTrial: Bool
    let periodValue: Int
    let periodUnit: Unit
    /// How many of those periods the offer runs for. Always 1 for a free trial on the App Store
    /// today, multiplied in anyway so a "1 week × 2" offer cannot be described as one week.
    let numberOfPeriods: Int

    init(isFreeTrial: Bool, periodValue: Int, periodUnit: Unit, numberOfPeriods: Int = 1) {
        self.isFreeTrial = isFreeTrial
        self.periodValue = periodValue
        self.periodUnit = periodUnit
        self.numberOfPeriods = numberOfPeriods
    }

    /// `nil` for a product with no introductory offer, or one RevenueCat describes in a unit this
    /// app has no words for.
    init?(_ discount: StoreProductDiscount?) {
        guard let discount else { return nil }
        let unit: Unit
        switch discount.subscriptionPeriod.unit {
        case .day: unit = .day
        case .week: unit = .week
        case .month: unit = .month
        case .year: unit = .year
        @unknown default: return nil
        }
        self.init(
            isFreeTrial: discount.paymentMode == .freeTrial,
            periodValue: discount.subscriptionPeriod.value,
            periodUnit: unit,
            numberOfPeriods: discount.numberOfPeriods
        )
    }
}

/// A free trial this Apple Account will actually get. Only ever built by `resolve`, so holding
/// one means both the offer and the eligibility check said yes.
struct FreeTrialOffer: Equatable {
    enum Unit: Equatable {
        case day, month, year
    }

    /// Weeks are folded into days, so a two-week trial reads "14-day", the way the copy has
    /// always put it and the way people count down a trial.
    let length: Int
    let unit: Unit

    /// Joins an offer to an eligibility answer. Anything short of a free trial and a plain
    /// `.eligible` is no trial.
    static func resolve(terms: IntroductoryOfferTerms?, eligibility: IntroOfferEligibility?) -> FreeTrialOffer? {
        guard let terms, terms.isFreeTrial, eligibility == .eligible else { return nil }
        let periods = terms.periodValue * max(terms.numberOfPeriods, 1)
        guard periods > 0 else { return nil }
        switch terms.periodUnit {
        case .day: return FreeTrialOffer(length: periods, unit: .day)
        case .week: return FreeTrialOffer(length: periods * 7, unit: .day)
        case .month: return FreeTrialOffer(length: periods, unit: .month)
        case .year: return FreeTrialOffer(length: periods, unit: .year)
        }
    }

    /// Every product's trial at once: only the products with both an offer and a yes appear.
    static func resolve(
        terms: [String: IntroductoryOfferTerms],
        eligibility: [String: IntroOfferEligibility]
    ) -> [String: FreeTrialOffer] {
        var trials: [String: FreeTrialOffer] = [:]
        for (id, offer) in terms {
            trials[id] = resolve(terms: offer, eligibility: eligibility[id])
        }
        return trials
    }

    private var unitWord: String {
        switch unit {
        case .day: "day"
        case .month: "month"
        case .year: "year"
        }
    }

    /// "14-day", "1-month": the adjective, for "Start my 14-day free trial".
    var lengthAdjective: String { "\(length)-\(unitWord)" }

    /// "14 days", "1 month": the noun, for "14 days free, then …".
    var duration: String { "\(length) \(unitWord)\(length == 1 ? "" : "s")" }

    /// The trial's length in days, where that is a fixed number. `nil` for months and years, whose
    /// length depends on the calendar, so nothing writes "Day 30" for a trial that is 28 days long.
    var dayCount: Int? { unit == .day ? length : nil }
}

/// What the paywall says about price, trial or not. Pure, so the one rule that matters (no trial
/// copy without a resolved trial) is tested where it is decided.
enum PaywallTrialCopy {
    static let subscribeTitle = "Subscribe"

    static func primaryTitle(trial: FreeTrialOffer?) -> String {
        guard let trial else { return subscribeTitle }
        return "Start my \(trial.lengthAdjective) free trial"
    }

    /// The disclosure under the button. With no trial it still states the price and that it
    /// renews, because that is what 3.1.2 asks the button's surroundings to make clear.
    static func caption(trial: FreeTrialOffer?, localizedPrice: String, periodLabel: String) -> String {
        guard let trial else { return "\(localizedPrice) a \(periodLabel). Renews automatically, cancel anytime." }
        return "\(trial.duration) free, then \(localizedPrice) a \(periodLabel)"
    }
}

/// Why the paywall called `onSubscribed`, so the next screen does not announce a trial that a
/// restore or a paid purchase never started.
enum SubscriptionOutcome: Equatable {
    /// A purchase completed. `freeTrial` is set only when the purchase actually began one.
    case purchased(freeTrial: FreeTrialOffer?)
    /// "Restore purchases" found an active subscription.
    case restored

    /// A completed purchase, described by what RevenueCat says it started. The entitlement's
    /// `periodType` is the authority on whether a trial began; the product's offer only supplies
    /// the length. Eligibility is not asked again, because a trial that is running is its answer.
    static func afterPurchase(entitlementIsInTrial: Bool, terms: IntroductoryOfferTerms?) -> SubscriptionOutcome {
        guard entitlementIsInTrial else { return .purchased(freeTrial: nil) }
        return .purchased(freeTrial: FreeTrialOffer.resolve(terms: terms, eligibility: .eligible))
    }

    /// `PurchaseSuccessView`'s subtitle.
    var successSubtitle: String {
        switch self {
        case .purchased(let trial?): "Your \(trial.lengthAdjective) free trial has started."
        case .purchased(nil): "Your subscription is active."
        case .restored: "Welcome back. Your subscription has been restored."
        }
    }
}
