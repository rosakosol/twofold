//
//  SubscriptionState.swift
//  Twofold
//
//  Whether this couple is subscribed, to which tier, and who in it pays. Owned by `AppModel`,
//  which forwards the old property names to it.
//

import Foundation
import Observation
import RevenueCat

@Observable
final class SubscriptionState: AccountScopedStore {
    /// "Your partner doesn't pay anything" — true if *either* partner's device last reported
    /// an active local StoreKit entitlement (see `BackendService.fetchSubscriptionActive`).
    /// `RootView` gates all of `MainTabView` behind this once `hasCouple` is true.
    var isActive = false
    /// Whether the signed-in person is the one paying, as opposed to either of them.
    ///
    /// `isActive` is the couple-wide OR and is what every gate reads. This is for copy addressed
    /// to the person in front of the screen — telling the partner of a subscriber to cancel a
    /// subscription is telling them to do something they cannot do and do not need to.
    var viewerHoldsSubscription = false
    /// "plus"/"premium", the higher of the two partners' tiers — nil for pre-existing
    /// subscribers from before this column existed (`start_game_session` treats that the same
    /// as "plus" server-side, so this being nil never actually locks anyone out of content).
    var tier: String?
    /// Where the viewer's *own* subscription was bought — `profiles.subscription_store`, written by
    /// `revenuecat-webhook` ("app_store", "rc_billing", "stripe", "promotional"…).
    ///
    /// The viewer's own row, never the couple-wide OR. What it is for is answering "where do I go to
    /// change this", and the website cannot cancel a subscription bought on the other partner's
    /// Apple Account any more than this app can. Nil is a real and common answer — nobody
    /// subscribed, a purchase older than migration 20261109000500, or a cold offline launch before
    /// the first fetch — so every reader has to treat it as "we don't know" and offer nothing on the
    /// strength of it.
    var viewerStore: String?

    /// Whether anything authoritative has said yet whether this account is subscribed.
    ///
    /// `isActive` is a plain Bool that starts `false`, so before the first answer lands "we do not
    /// know" is indistinguishable from "they have not paid" — and Home rendered the second. The
    /// card stopped *persisting* once the value stopped being clobbered by later refreshes, but it
    /// still flashed on every launch, which is the same third-state problem the invite card solved
    /// with `hasResolvedOutgoingConnectionRequest`.
    ///
    /// Set wherever a real answer is applied, including the ones that fail — an offline launch
    /// resolves from cache, and `RootView.checkSubscription` resolves in a `defer` so a thrown
    /// fetch still counts. Something that never resolves would hide the card from someone who
    /// genuinely has not paid, which is the failure worth avoiding here.
    private(set) var hasResolved = false

    /// For `RootView.checkSubscription`, whose own `defer` is the backstop for every path that does
    /// not go through an adopt.
    func markResolved() {
        hasResolved = true
    }

    /// What the backend said about this couple, reconciled with this device, as an adopt applies it.
    func apply(active: Bool, viewerHolds: Bool, tier: String?, viewerStore: String?) {
        isActive = active
        viewerHoldsSubscription = viewerHolds
        hasResolved = true
        self.tier = tier
        self.viewerStore = viewerStore
    }

    /// A device's own successful purchase/restore, applied instantly and locally (no network
    /// round-trip) — `PaywallView` calls `AppModel.markSubscriptionActive` right after a
    /// purchase/restore succeeds, before its own `onSubscribed()` callback fires, so `RootView`'s
    /// gate never flashes a second paywall for someone who just subscribed. Also updates `tier` —
    /// previously only the active flag was set here, so tier-gated UI (`isDeckLocked`/
    /// `isPremiumLocked`, Home's plan-dependent copy) stayed on the pre-purchase tier until the next
    /// foreground/relaunch's `performAdopt` round trip.
    func markActive(tier: String) {
        isActive = true
        hasResolved = true
        self.tier = tier
    }

    /// A re-read of the couple's subscription — on foreground, or when RevenueCat reports a change.
    ///
    /// Only trusts a `false` that actually saw the couple. Reported after joining a partner who
    /// pays: Home showed "No active subscription" and gated adding until Settings was opened, which
    /// ran the check again and fixed it. A lookup that cannot see the couple row falls back to the
    /// caller's own profile, and for the non-paying half of a couple that reads `false` —
    /// indistinguishable from nobody paying, and written straight over the couple-wide `true` that
    /// `performAdopt` had just set. `partnerConnected` is the app's own belief that a couple exists;
    /// when it says one does and the lookup disagrees, the lookup is the thing that is behind.
    ///
    /// OR'd with this device's own entitlement: a backend `false` for someone RevenueCat says is
    /// subscribed means the webhook has not caught up, not that they stopped paying. Without it the
    /// next foreground undoes the access the paywall just granted.
    func applyRefresh(_ snapshot: BackendService.SubscriptionSnapshot, deviceEntitled: Bool, partnerConnected: Bool) {
        guard snapshot.sawActiveCouple || !partnerConnected else { return }
        isActive = snapshot.active || deviceEntitled
    }

    func reset() {
        isActive = false
        // Read by the delete-account, disconnect and settings screens to tell the payer to cancel.
        // Left set, the next account was told to cancel a subscription it does not hold.
        viewerHoldsSubscription = false
        hasResolved = false
        // Tier, which gates content. A new free account inheriting "premium" sees premium decks
        // until the next refresh corrects it.
        tier = nil
        // Same reasoning one step further on: a new account inheriting "rc_billing" would be sent
        // to the website to manage a subscription belonging to whoever was signed in before.
        viewerStore = nil
    }

    // MARK: - Gates

    /// Whether this couple may add to their story — the client-side mirror of the RLS rule in
    /// 20261028000000.
    ///
    /// Reading and deleting are open to everyone; adding and editing need a subscription. The
    /// database is what actually enforces that, and this exists so somebody meets a paywall that
    /// explains itself rather than a write that fails for no stated reason. If the two ever
    /// disagree the database wins, which is the right way round — the worst this can do is offer
    /// a purchase to somebody who did not need one.
    ///
    /// `isActive` alone, deliberately. `tier` survives a lapse — it is the name of the plan
    /// somebody had, not proof they still have it — so ORing it in would hand every lapsed
    /// subscriber the thing this gate exists to withhold.
    ///
    /// The webhook-lag window is already covered: `markActive(tier:)` sets this flag locally the
    /// moment a purchase completes, well before the row is written.
    var canAddContent: Bool {
        isActive
    }

    /// The plan this couple is paying for right now: `tier` while `isActive`, nil once lapsed.
    ///
    /// `tier` is the name of the plan somebody had, and it outlives a lapse in more than one way:
    /// a foreground refresh that learns of the lapse changes `isActive` and leaves `tier` alone
    /// (the snapshot has no tier to give it), the solo path reads the raw profile column, which the
    /// webhook may leave set, and the offline cache records whatever was there. Every gate that
    /// unlocks something reads this, never `tier`, so a lapsed Premium couple meets the gate and
    /// the way back to Premium rather than features the server will refuse.
    var entitledTier: String? {
        isActive ? tier : nil
    }

    /// Same "Plus can see it exists, Premium unlocks it" shape as `isDeckLocked`, for non-deck
    /// features (e.g. the Flight Details screen's delay analysis/good-to-know/flight information
    /// cards) that are Premium-only but not backed by a `GameDeck` row. True for a lapsed Premium
    /// couple — see `entitledTier`. Nothing they made is touched: a locked screen shows the gate,
    /// and resubscribing (`markActive`) unlocks it again with everything where it was.
    var isPremiumLocked: Bool {
        entitledTier != "premium"
    }

    /// True if this deck requires a higher tier than the couple currently has — drives the
    /// unlock badge + premium-gate screen rather than hiding the deck outright.
    func isDeckLocked(_ deck: GameDeck) -> Bool {
        deck.tier == "premium" && isPremiumLocked
    }

    // MARK: - Reconciling with the device

    /// Whether somebody is subscribed, given what the backend row says and what this device's own
    /// RevenueCat customer says.
    ///
    /// The same OR `RootView.checkSubscription` applies on every foreground, pulled out as a pure
    /// function because the interesting case — backend behind, device ahead — is otherwise only
    /// reachable through `Purchases.shared`, which traps under XCTest.
    static func isSubscribed(backendSaysActive: Bool, deviceTier: SubscriptionTier?) -> Bool {
        backendSaysActive || deviceTier != nil
    }

    /// Whether this device can prove an entitlement for the account signed in right now.
    ///
    /// Same shape as `RootView.deviceHoldsEntitlement`, and the `isAnonymous` check is the
    /// load-bearing half for the same reason: an anonymous RevenueCat customer is whoever used this
    /// install before anybody signed in, so treating their entitlement as this account's would mean
    /// a device holding a subscription rather than a person.
    ///
    /// `customerInfo()` is served from the SDK's cache unless it is stale, so this is cheap.
    func deviceHoldsEntitlement() async -> Bool {
        await Self.deviceTier() != nil
    }

    /// This account's tier as the device's store reports it, or nil when it holds none — or when
    /// the store's customer is anonymous, which is somebody else as far as this account goes.
    ///
    /// An end-to-end test answers from `E2ELaunch.tier` instead, the way a signed-in RevenueCat
    /// customer would: the test seeds the server to match, so the two halves agree as they do for
    /// a real subscriber whose webhook has landed.
    static func deviceTier() async -> SubscriptionTier? {
        if let tier = E2ELaunch.tier { return tier.storeTier }
        guard Purchases.isConfigured, !Purchases.shared.isAnonymous,
              let info = try? await Purchases.shared.customerInfo() else { return nil }
        return SubscriptionTier.active(in: info)
    }

    /// The tier a store answer gives this account: what the store reported, unless its customer is
    /// anonymous — somebody else, for the reason `deviceHoldsEntitlement` gives.
    ///
    /// For an answer that arrives rather than one asked for: the live entitlement updates RootView
    /// listens to. That loop passed the store's tier on unchecked, the one place the device's
    /// answer was read without the anonymous check (CORE-26).
    static func deviceEntitlement(storeTier: SubscriptionTier?, customerIsAnonymous: Bool) -> SubscriptionTier? {
        customerIsAnonymous ? nil : storeTier
    }

    /// Whether this device's store customer is nobody in particular as far as the signed-in account
    /// goes: anonymous, or no store configured at all. Never in an end-to-end run, whose store
    /// answer stands for the account's own (see `deviceTier()`).
    static var storeCustomerIsAnonymous: Bool {
        if E2ELaunch.isOn { return false }
        return !Purchases.isConfigured || Purchases.shared.isAnonymous
    }

    /// What `isActive` should become, given what the backend just said.
    ///
    /// `profiles.subscription_active` is written by the RevenueCat webhook and lags a purchase by
    /// seconds to minutes. Every adopt path used to assign it straight over the top, which meant
    /// `markActive`'s optimistic `true` — set the instant a purchase succeeds — survived only until
    /// the next couple-state refresh. Home fires one on appear and on every foreground, so somebody
    /// who had just paid watched "No active subscription" arrive a few seconds after being let in.
    /// Reported twice, and the first fix was in the wrong place: it covered `loadSignedInState`,
    /// while onboarding admits people through `applyOnboardingAccount` and the clobber was happening
    /// in `refreshCoupleStateIfNeeded` regardless.
    ///
    /// Asking here rather than at each call site is what makes that impossible to get wrong again —
    /// there is no way to apply a backend subscription value without going through this.
    ///
    /// Only ever upgrades false -> true, and only on RevenueCat's own current answer for *this*
    /// account, so a genuine cancellation still reads as cancelled. `customerInfo()` is served from
    /// the SDK's cache unless it is stale, and this only asks when the backend said no, so the
    /// common path costs nothing.
    func resolvedActive(backendSaysActive: Bool) async -> Bool {
        if backendSaysActive { return true }
        let deviceTier = await Self.deviceTier()
        if deviceTier != nil {
            // This device is entitled and the row says otherwise, so the row is out of date — ask
            // the server to go and re-read RevenueCat.
            //
            // Nothing else closes this gap. A purchase made under an anonymous id is aliased to
            // the real one by the next `logIn`, but no re-sync follows it, and the nightly
            // `reconcile-subscriptions` selects profiles that are already active or recently
            // checked — a row stuck at false with a null `subscription_checked_at` is not in its
            // set, so it never self-heals. Every account that bought during onboarding before the
            // identify fix above is in exactly that state, and this is what repairs them on next
            // launch without anyone having to re-purchase or contact support.
            //
            // Detached, because the answer is not needed for this return: the local `deviceTier`
            // already gets this person into the app, and what the sync fixes is what their
            // *partner* sees. Rate limited to six an hour server-side, and only reached when the
            // backend said no, so a correctly-recorded subscriber never calls it at all.
            Task { await BackendService.syncSubscriptionFromStore() }
        }
        return Self.isSubscribed(backendSaysActive: false, deviceTier: deviceTier)
    }

    /// Whether a `profiles.subscription_store` value names a subscription billed through our own
    /// Stripe account, and therefore one the website can actually change.
    ///
    /// Mirrors `WEB_STORES` in site/src/lib/account/subscription.ts and the complement of
    /// `STORE_MANAGED` in supabase/functions/_shared/subscription-cancel.ts — three copies now, kept
    /// in sync by hand the same way this repo already accepts for `FlightStatus` and the support
    /// categories. There is no codegen between Swift, Deno and Next.
    ///
    /// Only a positively recognised web store returns true. Nil, empty and unrecognised all return
    /// false, which is the direction that fails safe: the cost of a false negative is a screen that
    /// says less than it could, and the cost of a false positive is sending an App Store subscriber
    /// to a website that cannot cancel anything for them — the mistake
    /// `site/src/lib/account/subscription.ts` was written to avoid, for the same reason.
    static func isWebManagedStore(_ store: String?) -> Bool {
        guard let store = store?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return store == "stripe" || store == "rc_billing"
    }
}
