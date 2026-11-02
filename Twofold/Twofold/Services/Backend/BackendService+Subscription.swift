//
//  BackendService+Subscription.swift
//  Twofold
//
//  Subscription access and tier, the store sync, and Relationship Record export credits.
//

import Foundation
import Supabase

extension BackendService {

    // MARK: - Subscription sync

    /// Asks the server to re-read this account's entitlement from RevenueCat now, rather than
    /// waiting for the purchase webhook to arrive.
    ///
    /// Since 20261028000000 the subscription check lives in RLS, and policies see the profile row
    /// rather than RevenueCat — so between a purchase completing and the webhook landing, somebody
    /// who has just paid cannot write anything. `markSubscriptionActive` gets them past the app's
    /// own gate immediately, but it deliberately does not touch those columns (that write is the
    /// webhook's alone), so it cannot help with the database's.
    ///
    /// Returns whether the row says active afterwards. Failure is not an error worth surfacing:
    /// the webhook or the nightly reconcile will get there, this only makes it sooner.
    @discardableResult
    static func syncSubscriptionFromStore() async -> Bool {
        struct Row: Decodable { var active: Bool }
        let row: Row? = try? await EdgeFunctions.invoke("sync-my-subscription")
        return row?.active ?? false
    }

    // MARK: - Record export credits

    /// How many bought-and-unspent Relationship Record exports this profile holds.
    ///
    /// Read straight from the table rather than through an RPC — the select policy already limits
    /// it to your own rows, so there is nothing an RPC would add but a round trip.
    static func recordExportCreditCount() async throws -> Int {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        struct Row: Decodable { let id: UUID }
        let rows: [Row] = try await supabase
            .from("record_export_credits")
            .select("id")
            .eq("profile_id", value: userID)
            .is("consumed_at", value: nil)
            .execute()
            .value
        return rows.count
    }

    /// Spends one credit. `false` means there was none to spend, which is a normal answer and not
    /// an error — the caller exports only on `true`.
    ///
    /// Premium never calls this: it exports without limit, and that is a tier check rather than a
    /// ledger entry. See 20261026000000.
    static func spendRecordExportCredit() async throws -> Bool {
        try await supabase.rpc("spend_record_export_credit").execute().value
    }

    // `subscription_active` / `subscription_tier` / `subscription_checked_at` are not written from
    // here any more, and cannot be: migration 20260915000000 rejects a write to those three columns
    // from `anon`/`authenticated`, so the PATCH this used to send now returns 403. The writer is
    // `supabase/functions/revenuecat-webhook`, running as service_role — see its header for why the
    // device's own word could not stay the source of truth (anyone with curl and the anon key that
    // ships in the app could grant themselves, and their partner, Premium).
    //
    // What went with it: a `SubscriptionStatusUpdate` payload that deliberately omitted a nil tier
    // so a routine re-check wouldn't blank the column, and an `isTrustworthyEntitlementSource`
    // guard that stopped a Debug build's local StoreKit — which always reports "not subscribed",
    // and which talks to production — from writing `active: false` onto a real subscriber's row.
    // Both were answers to problems only the client-side write had.


    /// The signed-in person's active couple, or nil when they are in none.
    ///
    /// The one place that asks. The same query was written out in `fetchCoupleState`
    /// and both subscription reads (CORE-21).
    static func activeCoupleRow() async throws -> CoupleRow? {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let rows: [CoupleRow] = try await supabase
            .from("couples")
            .select()
            .or("partner_a_id.eq.\(userID),partner_b_id.eq.\(userID)")
            .eq("status", value: "active")
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// The tier a couple has, from each partner's profile: Premium if either of them is on it,
    /// otherwise whichever tier an active partner has.
    ///
    /// Only a still-active row's tier counts. A lapsed partner's `subscription_tier` column is left
    /// stale rather than nulled out (the webhook writes `active: false` and leaves the tier alone),
    /// so an inactive row's tier must never be reported as the couple's plan, nor block a fresh
    /// purchase. Nil when nobody active has a tier, which includes subscribers from before the
    /// column existed.
    static func effectiveTier(_ profiles: [(active: Bool, tier: String?)]) -> String? {
        let activeTiers = profiles.compactMap { $0.active ? $0.tier : nil }
        return activeTiers.contains("premium") ? "premium" : activeTiers.first
    }

    private nonisolated struct SubscriptionTierRow: Decodable {
        var subscriptionActive: Bool
        var subscriptionTier: String?
        enum CodingKeys: String, CodingKey {
            case subscriptionActive = "subscription_active"
            case subscriptionTier = "subscription_tier"
        }
    }

    /// Whether anyone in the couple is paying, for which tier, and whether the answer actually
    /// covered a couple.
    ///
    /// Cheap and dedicated — deliberately not `fetchCoupleState()` (which also pulls trips,
    /// flights and memories), since this is re-checked on every foreground and whenever RevenueCat
    /// reports a change, not just once at cold launch. "Your partner doesn't pay anything": active
    /// if *either* partner's profile says so. Solo (unpaired) users only have their own row.
    ///
    /// One read for the access and the tier. They used to be two functions making the same two
    /// round trips, called one after the other, which was four where two do.
    struct SubscriptionSnapshot: Equatable {
        var active: Bool
        /// False when the answer covers only this user's own profile.
        ///
        /// Exists because the fallback is silent and the two cases it merges are not the same.
        /// "No active couple row came back" and "a couple came back and neither of them pays" both
        /// used to return plain `false`, so a lookup that could not see the couple — a read
        /// landing before the row is visible, a transient failure on that first query — reported
        /// the caller's own row as the whole truth. For somebody whose *partner* pays, that is
        /// `false`, and it was written straight over a correct `true`.
        var sawActiveCouple: Bool
        /// See `effectiveTier(_:)`.
        var tier: String?
    }

    static func fetchSubscriptionSnapshot() async throws -> SubscriptionSnapshot {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let couple = try await activeCoupleRow()
        let profileIDs = couple.map { [$0.partnerAId, $0.partnerBId] } ?? [userID]

        let rows: [SubscriptionTierRow] = try await supabase
            .from("profiles")
            .select("subscription_active, subscription_tier")
            .in("id", values: profileIDs)
            .execute()
            .value

        return SubscriptionSnapshot(
            active: rows.contains { $0.subscriptionActive },
            sawActiveCouple: couple != nil,
            tier: effectiveTier(rows.map { ($0.subscriptionActive, $0.subscriptionTier) })
        )
    }

    /// Which tier is active *right now* across both partners — `fetchSubscriptionSnapshot()`'s
    /// tier. Deliberately a fresh network fetch rather than reading `AppModel.subscriptionTier`,
    /// which can miss a partner's subscription that started after this device last loaded couple
    /// state. `PaywallView` calls this right before allowing a purchase for exactly that reason:
    /// App Store Connect's subscription-group exclusivity is per Apple ID, not per couple, so
    /// nothing on Apple's side stops each partner from independently subscribing to a different
    /// tier — only this app-side check can catch it before it turns into a second, real charge.
    static func fetchCoupleSubscriptionTier() async throws -> String? {
        try await fetchSubscriptionSnapshot().tier
    }

    /// Whether this couple is paying twice for one subscription, and which of them bought later.
    ///
    /// See migration 20261001000000. `redundantProfileID` is nil when the two purchase dates can't
    /// be compared — one is missing, or they are identical — which is a real answer, not a
    /// failure: the couple is still doubled up, and the app says so without naming anyone.
    struct RedundantSubscription: Decodable {
        var bothSubscribed: Bool
        var redundantProfileID: UUID?
        var iAmRedundant: Bool

        enum CodingKeys: String, CodingKey {
            case bothSubscribed = "both_subscribed"
            case redundantProfileID = "redundant_profile_id"
            case iAmRedundant = "i_am_redundant"
        }

        /// The couple is doubled up, and it is the partner rather than the caller who bought
        /// later. Distinct from `iAmRedundant` being false, which is also true when nobody could
        /// be identified.
        var partnerIsRedundant: Bool { bothSubscribed && redundantProfileID != nil && !iAmRedundant }
    }

    /// Answers for the caller's own couple. Returns a single row, always — "no overlap" is a row,
    /// so it can be told apart from a failed lookup.
    static func redundantSubscription() async throws -> RedundantSubscription? {
        let rows: [RedundantSubscription] = try await supabase
            .rpc("redundant_subscription")
            .execute()
            .value
        return rows.first
    }
}
