//
//  OfflineSessionCache.swift
//  Twofold
//
//  Last-known-good subscription state, persisted locally so a cold launch with no network doesn't
//  present a paying subscriber with the forced paywall.
//
//  The bug this exists for: `AppModel.loadSignedInState()` sets `hasCouple = true` unconditionally
//  (being authenticated at all means onboarding is done), but `isSubscriptionActive` was only ever
//  set from a *backend* read. Offline, `fetchCoupleState()`/`fetchOwnProfile()` both fail silently
//  behind `try?`, so it kept its `false` default and `RootView` fell through to
//  `PaywallView(isDismissable: false)` — reproduced on a cold launch with the backend unreachable.
//  For a flight-tracking app that's the worst possible moment for it: on a plane, app killed by
//  iOS, opened to check a flight.
//
//  Deliberately not solved with RevenueCat's own cached entitlement alone. That works for whoever
//  actually bought the subscription, but Twofold subscriptions are couple-wide — the partner who
//  *isn't* paying has no local entitlement to read, cached or otherwise, so they'd still be
//  paywalled offline. This records the couple-wide answer the backend already gave us.
//

import Foundation

enum OfflineSessionCache {
    private static let activeKey = "offlineSession.subscriptionActive"
    private static let tierKey = "offlineSession.subscriptionTier"
    private static let recordedAtKey = "offlineSession.recordedAt"
    private static let userIDKey = "offlineSession.userID"
    private static let partnerConnectedKey = "offlineSession.partnerConnected"
    private static let myNameKey = "offlineSession.myName"
    private static let partnerNameKey = "offlineSession.partnerName"
    private static let celebrationShownKey = "offlineSession.partnerConnectedCelebrationShown"
    private static let checklistDismissedKey = "offlineSession.setupChecklistDismissed"

    /// How long a cached "yes, subscribed" is honoured without any successful backend
    /// confirmation. Generous on purpose — this only ever applies while genuinely offline, and the
    /// app can't sync anything in that state anyway, so the realistic cost of a longer window is
    /// near zero while the cost of it being too short is locking a real subscriber out mid-trip.
    /// It exists at all so "stay offline forever" isn't an indefinite bypass.
    private static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    /// Called on every successful adopt — that's the moment the backend has just told us the
    /// couple-wide truth, so it's the only thing worth remembering.
    static func record(
        active: Bool,
        tier: String?,
        userID: UUID?,
        partnerConnected: Bool,
        myName: String?,
        partnerName: String?,
        celebrationShown: Bool,
        checklistDismissed: Bool
    ) {
        let defaults = UserDefaults.standard
        defaults.set(active, forKey: activeKey)
        defaults.set(tier, forKey: tierKey)
        defaults.set(Date().timeIntervalSince1970, forKey: recordedAtKey)
        defaults.set(userID?.uuidString, forKey: userIDKey)
        defaults.set(partnerConnected, forKey: partnerConnectedKey)
        defaults.set(myName, forKey: myNameKey)
        defaults.set(partnerName, forKey: partnerNameKey)
        defaults.set(celebrationShown, forKey: celebrationShownKey)
        defaults.set(checklistDismissed, forKey: checklistDismissedKey)
    }

    /// The last-known state, or nil when there isn't one, it's gone stale, or it belongs to a
    /// different account (a previous user on this device — never let their entitlement leak into
    /// whoever signed in after them).
    static func restore(for userID: UUID?) -> Snapshot? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: activeKey) != nil else { return nil }
        guard let userID, defaults.string(forKey: userIDKey) == userID.uuidString else { return nil }

        let recordedAt = defaults.double(forKey: recordedAtKey)
        guard recordedAt > 0, Date().timeIntervalSince1970 - recordedAt < maxAge else { return nil }

        return Snapshot(
            active: defaults.bool(forKey: activeKey),
            tier: defaults.string(forKey: tierKey),
            partnerConnected: defaults.bool(forKey: partnerConnectedKey),
            myName: defaults.string(forKey: myNameKey),
            partnerName: defaults.string(forKey: partnerNameKey),
            celebrationShown: defaults.bool(forKey: celebrationShownKey),
            checklistDismissed: defaults.bool(forKey: checklistDismissedKey)
        )
    }

    struct Snapshot {
        var active: Bool
        var tier: String?
        /// Restored so an offline cold launch doesn't tell a paired couple to "Set up your
        /// partner" (`needsPartnerInvite` is just `!partnerConnected`) — alarming in its own right,
        /// even once the paywall itself is out of the way.
        var partnerConnected: Bool
        var myName: String?
        var partnerName: String?
        /// One-time UI that must not replay every offline cold launch. Without these, restoring
        /// `partnerConnected` alone made the app re-run the "You're connected!" celebration on
        /// every launch with no network — trading one wrong state for another.
        var celebrationShown: Bool
        var checklistDismissed: Bool
    }

    /// Cleared on sign-out/account deletion alongside the rest of local session state, so the next
    /// person to use this device never inherits it.
    static func clear() {
        let defaults = UserDefaults.standard
        for key in [activeKey, tierKey, recordedAtKey, userIDKey, partnerConnectedKey, myNameKey, partnerNameKey, celebrationShownKey, checklistDismissedKey] {
            defaults.removeObject(forKey: key)
        }
    }
}
