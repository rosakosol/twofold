// Cancelling a web subscription on the owner's behalf, which is the only kind we can cancel.
//
// Deleting an account has never touched the subscription, and for an App Store purchase it never
// can: the subscription belongs to the Apple Account that bought it, and Apple gives developers no
// way to cancel one for somebody else. `DeleteAccountView` warns about that and links to Apple's
// own subscription management, and the FAQ says the same (20261105000000).
//
// A subscription bought on the website is different. It is billed through Stripe, we hold the
// credentials, and the person cannot cancel it themselves once their account is gone — there is no
// Apple Settings screen for it and no way left to sign in. The FAQ currently promises they can
// "email hello@twofoldapp.com.au and we will cancel it for you", which is a promise kept by hand,
// only for the people who think to ask, and only for as long as somebody is reading that inbox.
//
// So: cancel it during deletion, and treat a failure to cancel as a reason not to delete (see
// `delete-account`). Charging a deleted account is the one outcome worth refusing to risk.

/// RevenueCat's v1 subscriber payload, narrowed to what cancellation needs.
export interface RevenueCatSubscription {
  store?: string;
  expires_date?: string | null;
  store_transaction_id?: string | null;
  unsubscribe_detected_at?: string | null;
}

export interface ActiveSubscription {
  productId: string;
  store: string;
  storeTransactionId: string | null;
  expiresAt: string | null;
}

/// Stores where the subscription is the buyer's to cancel and nobody else's.
///
/// `promotional` is in here because there is no billing relationship to end — RevenueCat granted
/// it, it expires on its own, and there is no third party to call. Treating it as cancellable
/// would mean reporting a failure for something that was never a charge.
const STORE_MANAGED = new Set(["app_store", "play_store", "amazon", "promotional", "mac_app_store"]);

export function isStoreManaged(store: string): boolean {
  return STORE_MANAGED.has(store.trim().toLowerCase());
}

/// Subscriptions that have not yet expired, from a v1 `GET /subscribers/{id}` body.
///
/// `expires_date` is null for a lifetime/non-renewing grant, which counts as active — an absent
/// expiry is not an expiry in the past. Everything else is compared against `nowMs` rather than
/// trusting the entitlements map, because entitlements collapse several products into one answer
/// and cancellation needs the individual subscription that is still billing.
export function activeSubscriptions(
  subscriptions: Record<string, RevenueCatSubscription> | undefined,
  nowMs: number,
): ActiveSubscription[] {
  const out: ActiveSubscription[] = [];
  for (const [productId, sub] of Object.entries(subscriptions ?? {})) {
    const expiresAt = sub?.expires_date ?? null;
    if (expiresAt !== null) {
      const expiryMs = Date.parse(expiresAt);
      // An unparseable date is treated as still active on purpose: the cost of trying to cancel
      // something already finished is a no-op, and the cost of skipping something still billing is
      // a charge against a deleted account.
      if (Number.isFinite(expiryMs) && expiryMs <= nowMs) continue;
    }
    out.push({
      productId,
      store: (sub?.store ?? "unknown").trim().toLowerCase(),
      storeTransactionId: sub?.store_transaction_id ?? null,
      expiresAt,
    });
  }
  return out;
}

/// The subscriptions this function is able to end itself.
export function cancellableSubscriptions(active: ActiveSubscription[]): ActiveSubscription[] {
  return active.filter((s) => !isStoreManaged(s.store));
}

export async function fetchSubscriber(
  appUserId: string,
  apiKey: string,
  fetchImpl: typeof fetch = fetch,
): Promise<Record<string, RevenueCatSubscription> | null> {
  const response = await fetchImpl(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`,
    { headers: { Authorization: `Bearer ${apiKey}`, Accept: "application/json" } },
  );
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`RevenueCat API returned ${response.status}`);
  const body = await response.json();
  return body?.subscriber?.subscriptions ?? {};
}

/// RevenueCat reports a Stripe subscription's `store_transaction_id` as the subscription *item*
/// (`si_…`), not the subscription (`sub_…`), and Stripe's cancel endpoint takes the latter. One
/// extra lookup resolves it. Ids that already look like a subscription are passed through, since
/// nothing guarantees RevenueCat will keep reporting the item forever.
export async function resolveStripeSubscriptionId(
  storeTransactionId: string,
  stripeKey: string,
  fetchImpl: typeof fetch = fetch,
): Promise<string> {
  if (storeTransactionId.startsWith("sub_")) return storeTransactionId;
  if (!storeTransactionId.startsWith("si_")) {
    throw new Error(`unrecognised Stripe transaction id shape`);
  }
  const response = await fetchImpl(
    `https://api.stripe.com/v1/subscription_items/${encodeURIComponent(storeTransactionId)}`,
    { headers: { Authorization: `Bearer ${stripeKey}`, Accept: "application/json" } },
  );
  if (!response.ok) throw new Error(`Stripe subscription_items returned ${response.status}`);
  const body = await response.json();
  const subscriptionId = body?.subscription;
  if (typeof subscriptionId !== "string" || subscriptionId.length === 0) {
    throw new Error("Stripe subscription_item carried no subscription id");
  }
  return subscriptionId;
}

/// Cancels immediately rather than at period end.
///
/// At period end would leave a live subscription attached to an account that no longer exists,
/// renewing if the flag were ever cleared, and visible to nobody. The access it would preserve is
/// access to an app the person can no longer sign in to, so there is nothing to preserve. Stripe
/// issues no refund for either, which is the same outcome Apple gives.
export async function cancelStripeSubscription(
  subscriptionId: string,
  stripeKey: string,
  fetchImpl: typeof fetch = fetch,
): Promise<void> {
  const response = await fetchImpl(
    `https://api.stripe.com/v1/subscriptions/${encodeURIComponent(subscriptionId)}`,
    { method: "DELETE", headers: { Authorization: `Bearer ${stripeKey}` } },
  );
  // Already gone is the outcome we wanted. Stripe answers a second DELETE with 404, and a
  // re-called deletion must not fail on it — this whole function is meant to be safe to retry.
  if (response.status === 404) return;
  if (!response.ok) throw new Error(`Stripe cancel returned ${response.status}`);
}

/// Stops a subscription renewing, leaving the period already paid for intact.
///
/// The counterpart to `cancelStripeSubscription` above, and the difference is not a detail. That
/// one ends the subscription there and then, which is right for account deletion — the access it
/// would preserve is access to an app the person can no longer sign in to. It is wrong for
/// somebody who is cancelling and keeping their account: they have paid for a period, Stripe
/// refunds none of it, and ending it early takes away time they bought for nothing in return.
///
/// It is also the behaviour the rest of the codebase already assumes. `resolveWillRenew` exists
/// precisely because "cancelling does not end anything — it stops the renewal, and the entitlement
/// runs to the end of the period already paid for", and the app stops nagging a subscriber to
/// cancel on the strength of it. A portal that cancelled immediately would contradict the model
/// every other screen is built on.
export async function endStripeSubscriptionAtPeriodEnd(
  subscriptionId: string,
  stripeKey: string,
  fetchImpl: typeof fetch = fetch,
): Promise<void> {
  const response = await fetchImpl(
    `https://api.stripe.com/v1/subscriptions/${encodeURIComponent(subscriptionId)}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${stripeKey}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: "cancel_at_period_end=true",
    },
  );
  // A subscription Stripe no longer has is one nobody is being charged for, which is the outcome
  // asked for. Same reasoning as the 404 branch in cancelStripeSubscription: both are meant to be
  // safe to call twice.
  if (response.status === 404) return;
  if (!response.ok) throw new Error(`Stripe cancel-at-period-end returned ${response.status}`);
}

/// When the subscription should actually stop.
///
/// Explicit at every call site rather than defaulted, because the two callers want opposite things
/// and the wrong one is silent either way: `immediately` for a deletion, where nothing is left to
/// preserve, and `at_period_end` for a person who is staying and has paid through a date.
export type CancelMode = "immediately" | "at_period_end";

/// Ends every web subscription an account holds. Returns how many were acted on.
///
/// Throws if any of them could not be ended, and deliberately does not swallow — both callers
/// treat a failure as something the person must be told about rather than something to log. For
/// `delete-account` that means refusing to delete; for the account portal it means saying the
/// cancellation did not happen, so nobody is left believing a charge has stopped when it has not.
///
/// Shared so the two cannot drift. This logic lived inside delete-account, and a second copy in
/// the portal would be a pair that agrees in testing and disagrees in production, about money.
export async function cancelWebSubscriptions(
  appUserId: string,
  options: { revenueCatKey: string; stripeKey?: string; mode: CancelMode; fetchImpl?: typeof fetch },
): Promise<number> {
  const fetchImpl = options.fetchImpl ?? fetch;

  // Uppercased for the same reason the webhook does it: `Purchases.shared.logIn` sends the
  // uppercased UUID, so that is the id RevenueCat holds.
  const subscriptions = await fetchSubscriber(appUserId.toUpperCase(), options.revenueCatKey, fetchImpl);
  if (subscriptions === null) return 0;

  const cancellable = cancellableSubscriptions(activeSubscriptions(subscriptions, Date.now()));
  if (cancellable.length === 0) return 0;

  if (!options.stripeKey) {
    throw new Error("STRIPE_SECRET_KEY is not set, and this account has a web subscription");
  }

  for (const subscription of cancellable) {
    if (subscription.store !== "stripe" && subscription.store !== "rc_billing") {
      // An unrecognised store is not silently skipped: skipping is what leaves somebody paying.
      throw new Error(`no cancellation path for store "${subscription.store}"`);
    }
    if (!subscription.storeTransactionId) {
      throw new Error("web subscription carried no store transaction id");
    }
    // Both RevenueCat web stores bill through Stripe and report a Stripe id here.
    const stripeId = await resolveStripeSubscriptionId(
      subscription.storeTransactionId,
      options.stripeKey,
      fetchImpl,
    );
    if (options.mode === "immediately") {
      await cancelStripeSubscription(stripeId, options.stripeKey, fetchImpl);
    } else {
      await endStripeSubscriptionAtPeriodEnd(stripeId, options.stripeKey, fetchImpl);
    }
  }
  return cancellable.length;
}
