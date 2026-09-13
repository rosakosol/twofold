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

    /// The App Store Connect / RevenueCat product identifiers this app expects to exist.
    /// `SubscriptionStore.mapToPricedPackages` switches on these exact strings (matched against
    /// each package's `StoreProduct.productIdentifier`) to resolve which `SubscriptionTier` a
    /// package belongs to — RevenueCat's own `Package.packageType` can't tell Plus from Premium,
    /// since both have a monthly and an annual variant. These must match both the App Store
    /// Connect product IDs *and* whatever's attached to the current Offering in the RevenueCat
    /// dashboard exactly — a mismatch silently drops that package from the paywall rather than
    /// erroring, since an unrecognized identifier is treated as "not one of ours," not a crash.
    enum ProductIdentifier {
        static let monthlyPlus = "com.orangefinch.Twofold.plus.monthly"
        static let yearlyPlus = "com.orangefinch.Twofold.plus.yearly"
        static let monthlyPremium = "com.orangefinch.Twofold.premium.monthly"
        static let yearlyPremium = "com.orangefinch.Twofold.premium.yearly"

        /// A consumable, not a subscription, and the only one — bought to bridge a single missed
        /// day (see migration 20261007000000). It must never appear among the paywall's packages:
        /// `mapToPricedPackages` matches the four above and treats anything else as "not one of
        /// ours", which is what keeps a one-off purchase out of a screen selling plans.
        ///
        /// Buying it grants nothing by itself. The credit is written by the RevenueCat webhook
        /// against the store's transaction id, the same way entitlement is — the app's word that a
        /// purchase happened is not what a paid repair rests on.
        static let streakRepair = "com.orangefinch.Twofold.streak.repair"

        /// The second consumable, and the same rules apply: never a paywall package, and buying it
        /// grants nothing until the RevenueCat webhook writes a credit against the store's
        /// transaction id (see 20261026000000). One purchase, one Relationship Record export.
        ///
        /// Premium never reaches this. It exports without limit, which is a tier check rather than
        /// a credit — this exists for the people who would otherwise have to change plan to keep a
        /// document once.
        static let recordExport = "com.orangefinch.Twofold.record.export"
    }

    static func configure() {
        // Verbose while `.debug`; drop to `.warn` (or remove entirely — `.info` is the SDK
        // default) once the integration's been confirmed against a real RevenueCat dashboard.
        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        // Configured with the signed-in user's id when there already is one, rather than always
        // starting anonymous and being told later.
        //
        // `currentUserID` reads `supabase.auth.currentSession` synchronously off the locally-stored
        // session — no network, nothing to await — which is the same thing `AppModel.restoreSession`
        // relies on before its first await. So for anyone who has run the app before, the real id is
        // available here, at the first line of `TwofoldApp.init()`.
        //
        // This used to always start anonymous and rely on `Purchases.shared.logIn(_:)` from
        // `AppModel.loadSignedInState()` to alias the two afterwards. That leaves a window where
        // RevenueCat is anonymous, and anything that happens inside it — a purchase, a restore, a
        // customer-info fetch — attaches to an anonymous customer. If `logIn` then fails (a network
        // blip at launch is enough; see `identifyWithRevenueCat`'s retry) the aliasing never
        // happens and that customer is stranded, holding entitlements this backend will never ask
        // about, because it only ever queries the Supabase UUID.
        //
        // That is not theoretical. It produced two RevenueCat customers for one person, with a
        // lifetime entitlement granted on one and the webhook reading the other — which reported a
        // blank subscriber and wrote "no subscription" for someone who had one.
        //
        // A genuinely fresh install still starts anonymous, which is correct: there is no id to use
        // yet, and `logIn` aliases it the moment sign-in gives us one.
        Purchases.configure(withAPIKey: apiKey, appUserID: BackendService.currentUserID?.uuidString)
    }
}
