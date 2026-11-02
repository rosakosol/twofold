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


    private struct SubscriptionActiveRow: Decodable {
        var subscriptionActive: Bool
        enum CodingKeys: String, CodingKey { case subscriptionActive = "subscription_active" }
    }

    /// Cheap, dedicated status check — deliberately not `fetchCoupleState()` (which also pulls
    /// trips/flights/memories/places), since this needs to be re-checked periodically
    /// (app foreground), not just once at cold launch. "Your partner doesn't pay anything" —
    /// true if *either* partner's profile reports an active subscription; solo (unpaired)
    /// users only have their own row to check.
    /// Whether anyone is paying, and whether the answer actually covered a couple.
    ///
    /// `sawActiveCouple` exists because the fallback below is silent and the two cases it merges
    /// are not the same. "No active couple row came back" and "a couple came back and neither of
    /// them pays" both used to return plain `false`, so a lookup that could not see the couple —
    /// a read landing before the row is visible, a transient failure on that first query —
    /// reported the caller's own row as the whole truth. For somebody whose *partner* pays, that
    /// is `false`, and it was written straight over a correct `true`.
    struct SubscriptionAccess {
        var active: Bool
        /// False when the answer covers only this user's own profile.
        var sawActiveCouple: Bool
    }

    static func fetchSubscriptionAccess() async throws -> SubscriptionAccess {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }

        let coupleRows: [CoupleRow] = try await supabase
            .from("couples")
            .select()
            .or("partner_a_id.eq.\(userID),partner_b_id.eq.\(userID)")
            .eq("status", value: "active")
            .limit(1)
            .execute()
            .value

        let profileIDs: [UUID]
        if let couple = coupleRows.first {
            profileIDs = [couple.partnerAId, couple.partnerBId]
        } else {
            profileIDs = [userID]
        }

        let rows: [SubscriptionActiveRow] = try await supabase
            .from("profiles")
            .select("subscription_active")
            .in("id", values: profileIDs)
            .execute()
            .value

        return SubscriptionAccess(
            active: rows.contains { $0.subscriptionActive },
            sawActiveCouple: coupleRows.first != nil
        )
    }

    private struct SubscriptionTierRow: Decodable {
        var subscriptionActive: Bool
        var subscriptionTier: String?
        enum CodingKeys: String, CodingKey {
            case subscriptionActive = "subscription_active"
            case subscriptionTier = "subscription_tier"
        }
    }

    /// Same couple-wide lookup as `fetchSubscriptionActive()`, but resolves which tier is
    /// actually active *right now* across both partners (Premium wins if each partner
    /// independently ended up on a different tier). Deliberately a fresh network fetch rather
    /// than reading `AppModel.subscriptionTier` — that field is only set at couple-adoption time
    /// and never refreshed on foreground the way `isSubscriptionActive` is, so it can miss a
    /// partner's subscription that started after this device last loaded couple state. `PaywallView`
    /// calls this right before allowing a purchase for exactly that reason: App Store Connect's
    /// subscription-group exclusivity is per Apple ID, not per couple, so nothing on Apple's side
    /// stops each partner from independently subscribing to a different tier — only this app-side
    /// check can catch it before it turns into a second, real charge.
    static func fetchCoupleSubscriptionTier() async throws -> String? {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }

        let coupleRows: [CoupleRow] = try await supabase
            .from("couples")
            .select()
            .or("partner_a_id.eq.\(userID),partner_b_id.eq.\(userID)")
            .eq("status", value: "active")
            .limit(1)
            .execute()
            .value

        let profileIDs: [UUID]
        if let couple = coupleRows.first {
            profileIDs = [couple.partnerAId, couple.partnerBId]
        } else {
            profileIDs = [userID]
        }

        let rows: [SubscriptionTierRow] = try await supabase
            .from("profiles")
            .select("subscription_active, subscription_tier")
            .in("id", values: profileIDs)
            .execute()
            .value

        // Only a still-active row's tier counts — a lapsed partner's `subscription_tier` column is
        // left stale rather than nulled out (the webhook writes `active: false` and leaves the tier
        // alone), so an inactive row's tier must never block a fresh purchase.
        let activeTiers = rows.compactMap { $0.subscriptionActive ? $0.subscriptionTier : nil }
        return activeTiers.contains("premium") ? "premium" : activeTiers.first
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
