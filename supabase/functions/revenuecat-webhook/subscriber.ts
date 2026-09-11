// What a RevenueCat subscriber record means, with no network and no Deno.serve.
//
// Split out of index.ts so it can be tested at all: that module calls `Deno.serve` at import time,
// so importing it from a test starts a server. These are the decisions worth pinning — which tier
// is active, whether an entitlement has lapsed, and when the current subscription was bought.

// Must match RevenueCatConfig.Entitlement — these are dashboard identifiers, spaces and all.
export const ENTITLEMENT_PLUS = "Twofold Plus";
export const ENTITLEMENT_PREMIUM = "Twofold Premium";

export type Tier = "plus" | "premium" | null;

// One entitlement as the v1 REST API reports it. Note this endpoint returns *every* entitlement the
// subscriber has ever held, expired ones included — unlike the SDK's `entitlements.active`, which is
// already filtered. Deciding what counts as active is therefore our job; see isEntitlementActive.
export interface RestEntitlement {
  expires_date?: string | null;
  grace_period_expires_date?: string | null;
  purchase_date?: string | null;
  product_identifier?: string | null;
  [key: string]: unknown;
}

// One product under `subscriber.subscriptions`, keyed by product identifier.
export interface RestSubscription {
  original_purchase_date?: string | null;
  purchase_date?: string | null;
  unsubscribe_detected_at?: string | null;
  [key: string]: unknown;
}

export interface RestSubscriber {
  entitlements?: Record<string, RestEntitlement>;
  subscriptions?: Record<string, RestSubscription>;
  original_purchase_date?: string | null;
  [key: string]: unknown;
}

// ASSUMED semantics, matching RevenueCat's documented v1 response but not verified against a live
// subscriber: an entitlement is active while `expires_date` is in the future, or forever if it is
// null (a lifetime/non-consumable grant). `grace_period_expires_date` extends that window — during
// an unresolved billing issue Apple keeps serving the subscription and the SDK still reports the
// entitlement active, so treating it as lapsed here would cut off a paying customer mid-retry.
export function isEntitlementActive(entitlement: RestEntitlement | undefined, nowMs: number): boolean {
  if (!entitlement) return false;
  if (entitlement.expires_date === null || entitlement.expires_date === undefined) return true;

  let latestMs = 0;
  for (const value of [entitlement.expires_date, entitlement.grace_period_expires_date]) {
    if (typeof value !== "string") continue;
    const parsed = Date.parse(value);
    if (!Number.isNaN(parsed) && parsed > latestMs) latestMs = parsed;
  }
  return latestMs > nowMs;
}

/// A subscriber record with nothing in it at all — no entitlements, ever, and no subscriptions.
///
/// This is not the same as a lapsed subscriber, and telling them apart is the whole point.
/// `GET /v1/subscribers/{id}` CREATES the subscriber if it does not exist and returns 200 with
/// empty maps; it does not 404. So an id nobody has ever held — a typo, or more realistically a
/// real person whose entitlements are attached to a different app_user_id — is indistinguishable
/// from a genuine lapse, and both would be written as `active = false`.
///
/// That happened. A lifetime entitlement granted to one RevenueCat customer, while this backend
/// asked about a different id belonging to the same person, produced a blank subscriber and a row
/// saying they had nothing. The 404 branch in `fetchSubscriberState` exists to refuse exactly that
/// ("writing active = false off the back of a 404 would revoke a real subscription") and never
/// fires, because there is never a 404.
///
/// A lapse is safely distinguishable because this endpoint returns *every* entitlement a subscriber
/// has ever held, expired ones included — so someone who genuinely stopped paying still has a
/// non-empty `entitlements` map, and a purchase history besides. Only a record that has never held
/// anything comes back completely bare.
///
/// Treating bare as "no answer" rather than "no entitlement" is strictly the safer direction: it
/// cannot revoke someone whose access lives under an id we failed to ask about, and for a genuine
/// never-purchaser it changes nothing, since their row is already inactive.
export function isBlankSubscriber(subscriber: RestSubscriber): boolean {
  const entitlements = subscriber.entitlements ?? {};
  const subscriptions = subscriber.subscriptions ?? {};
  return Object.keys(entitlements).length === 0 && Object.keys(subscriptions).length === 0;
}

// Premium wins if both are active — the same rule as SubscriptionTier.active(in:), for the same
// separate-subscription-groups reason documented in index.ts.
export function resolveTier(entitlements: Record<string, RestEntitlement>, nowMs: number): Tier {
  if (isEntitlementActive(entitlements[ENTITLEMENT_PREMIUM], nowMs)) return "premium";
  if (isEntitlementActive(entitlements[ENTITLEMENT_PLUS], nowMs)) return "plus";
  return null;
}

/// When the active subscription was ORIGINALLY bought, as an ISO string, or null if it cannot be
/// determined. Null for a subscriber with no active tier — a lapsed subscription has no start.
///
/// Used for exactly one thing: deciding which partner of two subscribers is the redundant one (see
/// migration 20261001000000). It grants nothing, and null is handled — the app then says the two of
/// them are doubled up without naming either.
///
/// Original purchase, not the latest renewal, and the distinction is the whole point. The
/// entitlement's own `purchase_date` moves forward on every renewal, so a monthly subscriber of two
/// years would look newer than someone who bought an annual plan last month, and the wrong person
/// would be asked to cancel. `subscriptions[product].original_purchase_date` is the date that
/// stays put.
///
/// UNVERIFIED against a live subscriber. This matches RevenueCat's documented v1 shape, but nothing
/// in this repo has seen a real response body, so the lookup tries the documented location first
/// and then two fallbacks, and returns null rather than guessing if none of them are strings. If
/// production shows these coming back null for real subscribers, `subscriber.subscriptions` is the
/// thing to go and look at — `logMissingStart` below names what was actually present.
export function resolveStartedAt(subscriber: RestSubscriber, tier: Tier): string | null {
  if (tier === null) return null;

  const entitlement = subscriber.entitlements?.[tier === "premium" ? ENTITLEMENT_PREMIUM : ENTITLEMENT_PLUS];
  if (!entitlement) return null;

  const productId = entitlement.product_identifier;
  const subscription = typeof productId === "string" ? subscriber.subscriptions?.[productId] : undefined;

  // In preference order. The first is the one that is actually correct; the other two are better
  // than nothing, and both only differ from it for someone who has renewed or switched plans.
  for (
    const candidate of [
      subscription?.original_purchase_date,
      entitlement.purchase_date,
      subscription?.purchase_date,
    ]
  ) {
    if (typeof candidate !== "string") continue;
    const parsed = Date.parse(candidate);
    if (!Number.isNaN(parsed)) return new Date(parsed).toISOString();
  }

  return null;
}

/// Whether the active subscription is going to renew — false once a cancellation has been
/// detected, true while it is still running, null when we cannot tell.
///
/// The distinction exists because cancelling does not end anything. It stops the renewal, and the
/// entitlement runs to the end of the period already paid for, up to a year for an annual plan.
/// RevenueCat keeps reporting that entitlement active throughout, correctly — the person is still
/// entitled. Without this, someone who cancels goes on being told to cancel for the rest of their
/// paid year.
///
/// Null, not true, when the subscription record can't be found: `redundant_subscription` treats
/// unknown as "still renewing" so behaviour is unchanged for a profile the webhook hasn't seen
/// since this shipped, and that decision belongs in one place rather than being pre-empted here.
export function resolveWillRenew(subscriber: RestSubscriber, tier: Tier): boolean | null {
  if (tier === null) return null;

  const entitlement = subscriber.entitlements?.[tier === "premium" ? ENTITLEMENT_PREMIUM : ENTITLEMENT_PLUS];
  const productId = entitlement?.product_identifier;
  if (typeof productId !== "string") return null;

  const subscription = subscriber.subscriptions?.[productId];
  if (!subscription) return null;

  // Present and a string means RevenueCat has seen the cancellation. Absent or null means it has
  // not — which for a record it does hold is a real answer, not a missing one.
  return typeof subscription.unsubscribe_detected_at !== "string";
}

/// What to log when an active subscriber yields no start date. Turns the unverified assumption
/// above into something answerable from production logs, instead of something discovered by a user
/// being told to cancel the wrong subscription.
///
/// Field names, plus the product identifiers, which are the same handful of strings for every
/// subscriber and are already in the app binary. No dates and nothing else from the record: the
/// most likely reason this function returns null is that the entitlement's `product_identifier`
/// doesn't match any key of `subscriptions`, and that is exactly what these two lists show.
export function describeMissingStart(subscriber: RestSubscriber, tier: Tier): string {
  const key = tier === "premium" ? ENTITLEMENT_PREMIUM : ENTITLEMENT_PLUS;
  const entitlement = subscriber.entitlements?.[key];
  const productId = entitlement?.product_identifier;
  const subscription = typeof productId === "string" ? subscriber.subscriptions?.[productId] : undefined;
  return [
    `tier=${tier}`,
    `entitlementKeys=[${Object.keys(subscriber.entitlements ?? {}).join(",")}]`,
    `entitlementFields=[${Object.keys(entitlement ?? {}).join(",")}]`,
    `productIdentifier=${typeof productId === "string" ? "present" : "missing"}`,
    `subscriptionKeys=[${Object.keys(subscriber.subscriptions ?? {}).join(",")}]`,
    `subscriptionFields=[${Object.keys(subscription ?? {}).join(",")}]`,
  ].join(" ");
}
