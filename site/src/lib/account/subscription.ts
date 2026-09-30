/**
 * What a person can actually be offered about their own subscription, on the web.
 *
 * The question is never "are they subscribed" — it is "whose subscription is this to cancel".
 * An App Store subscription is Apple's; there is no API that ends one, which is why the app's own
 * DeleteAccountView links out to Apple's settings rather than offering a button. A website
 * subscription bills through Stripe with credentials we hold, and delete-account already cancels
 * one via _shared/subscription-cancel.ts.
 *
 * Getting this wrong in the permissive direction is the expensive mistake: a cancel button shown
 * to an App Store subscriber either does nothing or reports success for an action it cannot
 * perform, and they find out when they are charged again. So anything not positively known to be
 * ours resolves to "elsewhere", never to "ours".
 */

/** Mirrors STORE_MANAGED in supabase/functions/_shared/subscription-cancel.ts. Kept in sync by
 * hand, the same way this repo already accepts for FlightStatus and the support categories —
 * there is no shared codegen between Deno and Next. */
const STORE_MANAGED = new Set(["app_store", "play_store", "amazon", "promotional", "mac_app_store"]);

/** The two RevenueCat web stores, both of which bill through Stripe. */
const WEB_STORES = new Set(["stripe", "rc_billing"]);

export type SubscriptionControl =
  /** No active subscription. Nothing to manage. */
  | { kind: "none" }
  /** Ours to cancel, here, now. */
  | { kind: "web" }
  /** Someone else's — Apple, Google, or a grant. `storeLabel` names who, when we can. */
  | { kind: "elsewhere"; storeLabel: string; appleLink: boolean }
  /** Subscribed, but we do not know where it was bought. Offer nothing; explain honestly. */
  | { kind: "unknown" };

export interface SubscriptionSnapshot {
  active: boolean;
  tier: string | null;
  store: string | null;
  willRenew: boolean | null;
  startedAt: string | null;
  /// True while the subscription is in a free trial, null when unknown — see
  /// `profiles.subscription_is_trial`. Null must read as "we do not know", never as false: a
  /// trialist told they are on a paid period is told the wrong thing about their own money, and
  /// false is a claim rather than an absence.
  ///
  /// Says nothing about WHEN access stops on cancellation. An earlier version of this comment did,
  /// and was withdrawn by 20261111000200 — it was read off a sandbox subscription whose trial had
  /// converted in four minutes.
  isTrial: boolean | null;
}

const STORE_LABELS: Record<string, string> = {
  app_store: "the App Store",
  mac_app_store: "the Mac App Store",
  play_store: "Google Play",
  amazon: "Amazon",
  promotional: "a complimentary grant",
};

export function subscriptionControl(snapshot: SubscriptionSnapshot): SubscriptionControl {
  if (!snapshot.active) return { kind: "none" };

  const store = snapshot.store?.trim().toLowerCase() ?? "";

  // Null store is the common case for a while: every subscriber bought before the column existed
  // has nothing recorded until their next webhook event or the nightly reconcile. It has to read
  // as "we don't know yet", never as a default.
  if (store === "") return { kind: "unknown" };

  if (WEB_STORES.has(store)) return { kind: "web" };

  if (STORE_MANAGED.has(store)) {
    return {
      kind: "elsewhere",
      storeLabel: STORE_LABELS[store] ?? "another store",
      // Apple is the only one we can send someone straight to a working settings page for.
      appleLink: store === "app_store" || store === "mac_app_store",
    };
  }

  // A store RevenueCat has added since this list was written. Deliberately not treated as web,
  // which is the whole point of enumerating rather than defaulting.
  return { kind: "unknown" };
}

export function tierLabel(tier: string | null): string {
  if (tier === "premium") return "Twofold Premium";
  if (tier === "plus") return "Twofold Plus";
  // Only reachable for an active subscription whose tier we do not recognise — every caller is
  // inside an `active` branch. "No plan" was the old fallback and was the wrong thing to tell
  // somebody who is demonstrably paying for one.
  return "Twofold";
}

/**
 * What the caller's own billing history says, from `my_subscription_history()` (20261111001000).
 *
 * Separate from `SubscriptionSnapshot` because it comes from a different place and answers a
 * different question. The snapshot is `profiles`, which describes only now — the webhook nulls
 * `subscription_tier` and `subscription_started_at` the moment a subscription lapses, so a row for
 * somebody who paid for two years is identical to one for somebody who never paid at all. This
 * comes from the append-only event log, which remembers.
 */
export interface SubscriptionHistory {
  everSubscribed: boolean;
  lastTier: string | null;
  /// When it ended. Null while it is still running, and ALSO null for an ending that was never
  /// recorded — a lapse predating the log, or a reconcile with no event behind it. So null with
  /// `everSubscribed` true means "it ended, we cannot say when", which has to be said that way
  /// rather than guessed at.
  endedAt: string | null;
}

/** Null-safe read of the RPC's jsonb, for a payload that is shaped by SQL rather than by types. */
export function parseSubscriptionHistory(raw: unknown): SubscriptionHistory {
  const row = (raw ?? {}) as Record<string, unknown>;
  return {
    everSubscribed: row.ever_subscribed === true,
    lastTier: typeof row.last_tier === "string" ? row.last_tier : null,
    endedAt: typeof row.ended_at === "string" ? row.ended_at : null,
  };
}

/**
 * A date as every surface on the account page spells it.
 *
 * One copy because there were two — SubscriptionCard and DangerZone had written the same function
 * independently, which is how a subscription's end date and an archive's purge date come to be
 * formatted differently on one screen.
 *
 * Returns null rather than "Invalid Date" for input it cannot read, so a caller can fall through to
 * its own undated wording instead of printing something that looks like a bug to the person whose
 * account it is.
 */
export function longDate(iso: string | null): string | null {
  if (!iso) return null;
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return null;
  return date.toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" });
}

/** Apple's own subscription management page. Works on desktop and deep-links on iOS. */
export const APPLE_SUBSCRIPTIONS_URL = "https://apps.apple.com/account/subscriptions";
