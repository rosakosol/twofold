// Cancelling a web subscription on the owner's behalf, which is the only kind we can cancel.
//
// Deleting an account has never touched the subscription, and for an App Store purchase it never
// can: the subscription belongs to the Apple Account that bought it, and Apple gives developers no
// way to cancel one for somebody else. `DeleteAccountView` warns about that and links to Apple's
// own subscription management, and the FAQ says the same (20261105000000).
//
// A subscription bought on the website is different — it is ours to end, and the person cannot do
// it themselves once their account is gone. So: cancel it during deletion, and treat a failure to
// cancel as a reason not to delete (see `delete-account`). Charging a deleted account is the one
// outcome worth refusing to risk.
//
// ---------------------------------------------------------------------------
// Why this talks to RevenueCat rather than Stripe
// ---------------------------------------------------------------------------
//
// It used to call Stripe directly: read the subscriber from RevenueCat's v1 API, pull
// `store_transaction_id`, resolve the Stripe subscription *item* (`si_…`) to its subscription
// (`sub_…`), and cancel that. It had to, because the web provider was Stripe Billing — RevenueCat
// did not own those subscriptions and had no endpoint that could end one.
//
// The web provider is RevenueCat Billing now, so RevenueCat owns them and will cancel them itself.
// That removes the Stripe secret from this path entirely, along with the `si_…` shape assumption
// that was never verified against a live response and that `delete-account` silently depended on.
//
// ---------------------------------------------------------------------------
// Period end, not immediately
// ---------------------------------------------------------------------------
//
// Deletion used to cancel immediately, on the reasoning that the access it would preserve is access
// to an app the person can no longer sign in to. RevenueCat's cancel endpoint is period-end only —
// ending one on the spot means refunding it, which is a different decision and not one account
// deletion should make on somebody's behalf.
//
// Period end is the right answer anyway, and the old reasoning was thin. What matters is that no
// further charge ever occurs, and cancelling stops the renewal that would cause one. Stripe refunds
// nothing for an immediate cancellation, so ending it early only took away time already paid for.
//
// ---------------------------------------------------------------------------
// Requires
// ---------------------------------------------------------------------------
//
//   - REVENUECAT_REST_API_KEY — a RevenueCat secret API key with v2 permissions. The v1-only keys
//     that predate the v2 API will 401 here.
//   - REVENUECAT_PROJECT_ID   — the project these customers live in; every v2 path is scoped to it.

const REVENUECAT_API_BASE = "https://api.revenuecat.com/v2";

/// Stores where the subscription is the buyer's to cancel and nobody else's.
///
/// `promotional` is in here because there is no billing relationship to end — RevenueCat granted
/// it, it expires on its own, and there is no third party to call. Treating it as cancellable
/// would mean reporting a failure for something that was never a charge.
const STORE_MANAGED = new Set(["app_store", "play_store", "amazon", "promotional", "mac_app_store"]);

/// The one store RevenueCat's own cancel endpoint accepts. Documented as "Web Billing subscriptions
/// only", so anything else that is still billing has to be refused rather than attempted.
const REVENUECAT_CANCELLABLE = "rc_billing";

/// How many pages of subscriptions to walk before giving up. Nobody holds a thousand subscriptions;
/// this exists so a malformed `next_page` cannot spin forever against a paid API.
const MAX_PAGES = 10;

/// RevenueCat's v2 Subscription, narrowed to what cancellation needs.
export interface Subscription {
  /// RevenueCat's own id — what the cancel endpoint takes. Not the store's id.
  id: string;
  /// amazon | app_store | mac_app_store | play_store | promotional | stripe | rc_billing | …
  store: string;
  /// RevenueCat's own answer to "should this customer have access right now", which replaces the
  /// expiry arithmetic this file used to do against `expires_date`. Worth taking over our own
  /// reading: it accounts for grace periods and billing retries, which a date comparison does not.
  gives_access: boolean;
  /// will_renew | will_not_renew | will_change_product | …
  auto_renewal_status?: string;
  product_id?: string | null;
}

export function isStoreManaged(store: string): boolean {
  return STORE_MANAGED.has(store.trim().toLowerCase());
}

/// Already cancelled, so there is nothing to do and nothing to report as failed. Kept separate from
/// the store check because the two mean different things: this one *was* ours and has been dealt
/// with. Calling cancel again would be asking RevenueCat to end an already-ending subscription,
/// which is how an idempotent path starts returning errors.
function alreadyCancelled(subscription: Subscription): boolean {
  return subscription.auto_renewal_status === "will_not_renew";
}

export interface Partitioned {
  /// Ours, live, and RevenueCat will end them.
  cancellable: Subscription[];
  /// Apple's or Google's, or a grant. Reporting zero for these is correct, not a failure.
  storeManaged: Subscription[];
  /// Still granting access, still capable of billing, and nothing here can stop it — a subscription
  /// left on the old Stripe provider, or a store we have never sold through. Never silently
  /// skipped: skipping is what leaves somebody paying.
  unsupported: Subscription[];
}

/// Sorts what a customer holds into what this function can do about each of them.
///
/// Anything not currently granting access is dropped first. An expired subscription is not billing
/// anyone and cancelling it would be a no-op at best.
export function partitionForCancellation(subscriptions: Subscription[]): Partitioned {
  const out: Partitioned = { cancellable: [], storeManaged: [], unsupported: [] };

  for (const subscription of subscriptions) {
    if (!subscription.gives_access) continue;

    const store = subscription.store.trim().toLowerCase();
    if (isStoreManaged(store)) {
      out.storeManaged.push(subscription);
    } else if (store === REVENUECAT_CANCELLABLE) {
      if (!alreadyCancelled(subscription)) out.cancellable.push(subscription);
    } else {
      out.unsupported.push(subscription);
    }
  }

  return out;
}

interface SubscriptionPage {
  items?: Subscription[];
  next_page?: string | null;
}

/// Every subscription RevenueCat holds for this customer id, following pagination.
///
/// A 404 is an id RevenueCat has never heard of, which is a customer with no subscriptions rather
/// than an error — the caller asks under two spellings and at most one of them will exist.
export async function listCustomerSubscriptions(
  projectId: string,
  customerId: string,
  apiKey: string,
  fetchImpl: typeof fetch = fetch,
): Promise<Subscription[]> {
  const subscriptions: Subscription[] = [];
  let url: string | null =
    `${REVENUECAT_API_BASE}/projects/${encodeURIComponent(projectId)}` +
    `/customers/${encodeURIComponent(customerId)}/subscriptions?limit=100`;

  for (let page = 0; url && page < MAX_PAGES; page += 1) {
    const response: Response = await fetchImpl(url, {
      headers: { Authorization: `Bearer ${apiKey}`, Accept: "application/json" },
    });
    if (response.status === 404) return [];
    if (!response.ok) throw new Error(`RevenueCat API returned ${response.status}`);

    const body = await response.json() as SubscriptionPage;
    subscriptions.push(...(body.items ?? []));

    // `next_page` is documented as a URL. Relative is handled too rather than assumed away, since
    // the alternative is a silently truncated list and a subscription that keeps billing.
    const next = body.next_page;
    url = !next ? null : next.startsWith("http") ? next : `${REVENUECAT_API_BASE}${next}`;
  }

  return subscriptions;
}

/// Stops a subscription renewing, leaving the period already paid for intact.
///
/// RevenueCat has no immediate-cancel; ending one on the spot is the refund endpoint, which this
/// deliberately does not call. See the header.
export async function cancelSubscription(
  projectId: string,
  subscriptionId: string,
  apiKey: string,
  fetchImpl: typeof fetch = fetch,
): Promise<void> {
  const response = await fetchImpl(
    `${REVENUECAT_API_BASE}/projects/${encodeURIComponent(projectId)}` +
      `/subscriptions/${encodeURIComponent(subscriptionId)}/actions/cancel`,
    { method: "POST", headers: { Authorization: `Bearer ${apiKey}`, Accept: "application/json" } },
  );
  // Already gone is the outcome we wanted, and this whole path is meant to be safe to retry.
  if (response.status === 404) return;
  if (!response.ok) throw new Error(`RevenueCat cancel returned ${response.status}`);
}

/// Ends every web subscription an account holds. Returns how many were acted on.
///
/// Throws if any of them could not be ended, and deliberately does not swallow — both callers treat
/// a failure as something the person must be told about rather than something to log. For
/// `delete-account` that means refusing to delete; for the account portal it means saying the
/// cancellation did not happen, so nobody is left believing a charge has stopped when it has not.
export async function cancelWebSubscriptions(
  appUserId: string,
  options: { projectId: string; revenueCatKey: string; fetchImpl?: typeof fetch },
): Promise<number> {
  const fetchImpl = options.fetchImpl ?? fetch;

  // Both spellings, because one person can be two customer ids. Swift's `UUID.uuidString` uppercases
  // and that is what `Purchases.logIn` sends, while Postgres holds uuids lowercase and the website
  // used to buy under that form. Deduped on RevenueCat's own subscription id, so a customer that
  // answers to both spellings is not cancelled twice.
  const spellings = [...new Set([appUserId.toUpperCase(), appUserId.toLowerCase()])];
  const byId = new Map<string, Subscription>();
  for (const spelling of spellings) {
    for (const subscription of await listCustomerSubscriptions(options.projectId, spelling, options.revenueCatKey, fetchImpl)) {
      byId.set(subscription.id, subscription);
    }
  }

  const { cancellable, unsupported } = partitionForCancellation([...byId.values()]);

  // Before cancelling anything, so a mixed set does not half-succeed and report a number that
  // implies the rest were fine.
  if (unsupported.length > 0) {
    const stores = [...new Set(unsupported.map((s) => s.store))].join(", ");
    throw new Error(`no cancellation path for store "${stores}"`);
  }

  for (const subscription of cancellable) {
    await cancelSubscription(options.projectId, subscription.id, options.revenueCatKey, fetchImpl);
  }

  return cancellable.length;
}
