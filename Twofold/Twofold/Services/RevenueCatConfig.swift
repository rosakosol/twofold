//
//  RevenueCatConfig.swift
//  Twofold
//
//  One-time SDK bring-up, called from `TwofoldApp.init()` before anything else touches
//  `Purchases.shared` — every other RevenueCat call in the app (`SubscriptionStore`,
//  `AppModel`'s identity sync, the paywall/Customer Center views) assumes `configure()` has
//  already run. Kept separate from `SubscriptionStore` since this only ever runs once per
//  process, unlike everything else in that file.
//


import Foundation
import RevenueCat

enum RevenueCatConfig {
    /// The real "Apple App Store" public API key from the RevenueCat dashboard (Project
    /// settings → API keys) — a `test_...` Test Store key was used here during development,
    /// but RevenueCat's SDK deliberately fatal-crashes if it detects one running inside a
    /// Release-configured build (which every TestFlight archive is), as a guardrail against
    /// shipping a sandbox key by accident.
    static let apiKey = "appl_DoPckVWWpcnAifAJxyqVrIgqGna"

    /// The two entitlements configured in the RevenueCat dashboard, one per subscription tier —
    /// mirrors `SubscriptionTier`, see that enum for the couple-facing display/DB-value side of
    /// the same two tiers.
    enum Entitlement {
        static let plus = "Twofold Plus"
        static let premium = "Twofold Premium"
    }

    /// The 4 App Store Connect / RevenueCat product identifiers this app expects to exist.
    /// Referenced here for documentation only — the RevenueCatUI paywall (`PaywallView`)
    /// resolves packages entirely from whichever Offering is marked "current" in the RevenueCat
    /// dashboard, so nothing in this app's Swift code looks these strings up directly. This is
    /// the source of truth for what to create in App Store Connect and attach to an Offering +
    /// one of the two `Entitlement`s above in the RevenueCat dashboard.
    enum ProductIdentifier {
        static let monthlyPlus = "subscription_monthly_plus"
        static let yearlyPlus = "subscription_yearly_plus"
        static let monthlyPremium = "subscription_monthly_premium"
        static let yearlyPremium = "subscription_yearly_premium"
    }

    static func configure() {
        // Verbose while `.debug`; drop to `.warn` (or remove entirely — `.info` is the SDK
        // default) once the integration's been confirmed against a real RevenueCat dashboard.
        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        // No `appUserID:` here — at this point in `TwofoldApp.init()` we haven't restored the
        // Supabase session yet, so RevenueCat starts with its own anonymous ID and gets told the
        // real one via `Purchases.shared.logIn(_:)` from `AppModel.loadSignedInState()` the
        // moment a signed-in user is known (see that method).
        Purchases.configure(withAPIKey: apiKey)
    }
}
