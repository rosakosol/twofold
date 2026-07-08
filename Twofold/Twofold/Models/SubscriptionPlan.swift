//
//  SubscriptionPlan.swift
//  Twofold
//

import Foundation

enum SubscriptionTier: String, CaseIterable, Identifiable {
    case free = "Twofold Free"
    case plus = "Twofold+"
    case frequent = "Twofold Frequent"

    var id: String { rawValue }
}

struct SubscriptionPlan: Identifiable {
    let id: SubscriptionTier
    var monthlyPrice: String
    var yearlyPrice: String?
    var yearlySavingsLabel: String?
    var trackedFlightsPerMonth: Int
    var isMostPopular: Bool

    static let plus = SubscriptionPlan(
        id: .plus,
        monthlyPrice: "$9.99",
        yearlyPrice: "$69.99",
        yearlySavingsLabel: "Save 42%",
        trackedFlightsPerMonth: 10,
        isMostPopular: true
    )

    static let frequent = SubscriptionPlan(
        id: .frequent,
        monthlyPrice: "$19.99",
        yearlyPrice: "$149.99",
        yearlySavingsLabel: "Save 37%",
        trackedFlightsPerMonth: 100,
        isMostPopular: false
    )

    static let all: [SubscriptionPlan] = [.plus, .frequent]
}
