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
