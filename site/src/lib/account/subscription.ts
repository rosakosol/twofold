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
  return "No plan";
}

/** Apple's own subscription management page. Works on desktop and deep-links on iOS. */
export const APPLE_SUBSCRIPTIONS_URL = "https://apps.apple.com/account/subscriptions";
