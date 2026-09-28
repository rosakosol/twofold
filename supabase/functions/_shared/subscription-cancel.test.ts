// The classification is the load-bearing part: get it wrong towards "store managed" and a web
// subscriber keeps being charged after deleting their account, get it wrong the other way and
// deletion fails for every App Store subscriber because there is nothing we can cancel.

import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  activeSubscriptions,
  cancellableSubscriptions,
  cancelStripeSubscription,
  isStoreManaged,
  cancelWebSubscriptions,
  resolveStripeSubscriptionId,
} from "./subscription-cancel.ts";

const NOW = Date.parse("2026-09-21T00:00:00Z");

Deno.test("Apple and Google subscriptions are the buyer's to cancel, not ours", () => {
  for (const store of ["app_store", "play_store", "amazon", "mac_app_store"]) {
    assertEquals(isStoreManaged(store), true, store);
  }
  // RevenueCat sends uppercase in webhook events and lowercase from the REST API.
  assertEquals(isStoreManaged("APP_STORE"), true);
});

Deno.test("a promotional grant is not a charge, so not something to cancel", () => {
  assertEquals(isStoreManaged("promotional"), true);
});

Deno.test("web stores are ours to cancel", () => {
  assertEquals(isStoreManaged("stripe"), false);
  assertEquals(isStoreManaged("rc_billing"), false);
});

Deno.test("an expired subscription is not active", () => {
  const active = activeSubscriptions({
    "twofold.plus.monthly": { store: "stripe", expires_date: "2026-09-20T00:00:00Z" },
  }, NOW);
  assertEquals(active.length, 0);
});

Deno.test("a subscription expiring in the future is active", () => {
  const active = activeSubscriptions({
    "twofold.plus.monthly": {
      store: "STRIPE",
      expires_date: "2026-10-21T00:00:00Z",
      store_transaction_id: "si_abc123",
    },
  }, NOW);
  assertEquals(active.length, 1);
  assertEquals(active[0].store, "stripe", "store is normalised for comparison");
  assertEquals(active[0].storeTransactionId, "si_abc123");
});

Deno.test("a null expiry counts as active rather than as expired", () => {
  // A lifetime grant. Reading "no expiry" as "expired" would skip a live subscription.
  const active = activeSubscriptions({
    "twofold.lifetime": { store: "stripe", expires_date: null },
  }, NOW);
  assertEquals(active.length, 1);
});

Deno.test("only the web subscription is put forward for cancellation", () => {
  const active = activeSubscriptions({
    "twofold.plus.monthly": { store: "app_store", expires_date: "2026-10-21T00:00:00Z" },
    "twofold.premium.web": { store: "stripe", expires_date: "2026-10-21T00:00:00Z", store_transaction_id: "si_x" },
  }, NOW);
  const cancellable = cancellableSubscriptions(active);
  assertEquals(cancellable.length, 1);
  assertEquals(cancellable[0].productId, "twofold.premium.web");
});

// ---------------------------------------------------------------------------
// Stripe
// ---------------------------------------------------------------------------

Deno.test("a subscription item id is resolved to its subscription", async () => {
  const calls: string[] = [];
  const fakeFetch = ((url: string) => {
    calls.push(String(url));
    return Promise.resolve(new Response(JSON.stringify({ subscription: "sub_real" }), { status: 200 }));
  }) as unknown as typeof fetch;

  const id = await resolveStripeSubscriptionId("si_abc123", "sk_test", fakeFetch);
  assertEquals(id, "sub_real");
  assertEquals(calls[0], "https://api.stripe.com/v1/subscription_items/si_abc123");
});

Deno.test("a subscription id is used as-is, with no lookup", async () => {
  const fakeFetch = (() => {
    throw new Error("should not have called Stripe");
  }) as unknown as typeof fetch;
  assertEquals(await resolveStripeSubscriptionId("sub_direct", "sk_test", fakeFetch), "sub_direct");
});

Deno.test("an unrecognised transaction id is refused rather than guessed at", async () => {
  const fakeFetch = (() => {
    throw new Error("should not have called Stripe");
  }) as unknown as typeof fetch;
  await assertRejects(() => resolveStripeSubscriptionId("1000000123456789", "sk_test", fakeFetch));
});

Deno.test("cancelling twice succeeds, because deletion is retried", async () => {
  // The whole delete flow is documented as safe to re-call. Stripe answers the second DELETE with
  // 404, and treating that as a failure would make a retried deletion impossible to complete.
  const fakeFetch = (() => Promise.resolve(new Response("{}", { status: 404 }))) as unknown as typeof fetch;
  await cancelStripeSubscription("sub_gone", "sk_test", fakeFetch);
});

Deno.test("a real Stripe failure is surfaced, not swallowed", async () => {
  const fakeFetch = (() => Promise.resolve(new Response("{}", { status: 500 }))) as unknown as typeof fetch;
  await assertRejects(() => cancelStripeSubscription("sub_x", "sk_test", fakeFetch));
});

Deno.test("cancel uses DELETE, so nothing is left scheduled", async () => {
  let method = "";
  const fakeFetch = ((_url: string, init: RequestInit) => {
    method = String(init?.method);
    return Promise.resolve(new Response("{}", { status: 200 }));
  }) as unknown as typeof fetch;
  await cancelStripeSubscription("sub_x", "sk_test", fakeFetch);
  assertEquals(method, "DELETE");
});

// ---------------------------------------------------------------------------
// Immediately, versus at the end of the period already paid for
// ---------------------------------------------------------------------------
//
// The two callers want opposite things and the wrong one is silent either way.
//
// Deleting an account cancels immediately, and should: what an end-of-period cancellation would
// preserve is access to an app the person can no longer sign in to.
//
// The account portal cancels at period end, and must: the person is staying, they have paid
// through a date, and Stripe refunds none of it. Cancelling immediately there would take away time
// they bought and give nothing back — a support complaint manufactured by our own button, and one
// that contradicts the model resolveWillRenew and the app's own copy are built on.

function stripeRecorder() {
  const calls: Array<{ url: string; method: string; body: string | null }> = [];
  const fetchImpl = ((url: string | URL, init?: RequestInit) => {
    calls.push({
      url: String(url),
      method: init?.method ?? "GET",
      body: typeof init?.body === "string" ? init.body : null,
    });
    // The RevenueCat subscriber lookup comes first; everything after is Stripe.
    if (String(url).includes("api.revenuecat.com")) {
      return Promise.resolve(
        new Response(
          JSON.stringify({
            subscriber: {
              subscriptions: {
                web_premium: { store: "stripe", expires_date: null, store_transaction_id: "sub_live" },
              },
            },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    }
    return Promise.resolve(new Response("{}", { status: 200, headers: { "content-type": "application/json" } }));
  }) as typeof fetch;
  return { calls, fetchImpl };
}

Deno.test("the portal stops the renewal and leaves the paid period alone", async () => {
  const { calls, fetchImpl } = stripeRecorder();

  const cancelled = await cancelWebSubscriptions("abc", {
    revenueCatKey: "rc",
    stripeKey: "sk",
    mode: "at_period_end",
    fetchImpl,
  });

  assertEquals(cancelled, 1);
  const stripeCall = calls.find((c) => c.url.includes("api.stripe.com/v1/subscriptions/"));
  assertEquals(stripeCall?.method, "POST", "a DELETE here would end it on the spot");
  assertEquals(stripeCall?.body, "cancel_at_period_end=true");
});

Deno.test("deleting an account ends it on the spot", async () => {
  const { calls, fetchImpl } = stripeRecorder();

  const cancelled = await cancelWebSubscriptions("abc", {
    revenueCatKey: "rc",
    stripeKey: "sk",
    mode: "immediately",
    fetchImpl,
  });

  assertEquals(cancelled, 1);
  const stripeCall = calls.find((c) => c.url.includes("api.stripe.com/v1/subscriptions/"));
  assertEquals(stripeCall?.method, "DELETE");
});

Deno.test("an App Store subscription is reported as nothing to cancel, not as a failure", async () => {
  // The portal shows Apple's own settings link for this case. Throwing would turn "we can't do
  // this for you" into an error screen; reporting success for it would be far worse — the person
  // would believe a charge had stopped that is still coming.
  const fetchImpl = ((url: string | URL) => {
    if (String(url).includes("api.revenuecat.com")) {
      return Promise.resolve(
        new Response(
          JSON.stringify({
            subscriber: {
              subscriptions: {
                ios_premium: { store: "app_store", expires_date: null, store_transaction_id: "1000" },
              },
            },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    }
    throw new Error("Stripe must not be called for an App Store subscription");
  }) as typeof fetch;

  const cancelled = await cancelWebSubscriptions("abc", {
    revenueCatKey: "rc",
    stripeKey: "sk",
    mode: "at_period_end",
    fetchImpl,
  });
  assertEquals(cancelled, 0);
});

Deno.test("a web subscription with no Stripe key throws rather than reporting success", async () => {
  // Reporting 0 here would read to the caller as "nothing to cancel", and the person would be told
  // their subscription was already inactive while it went on billing.
  const { fetchImpl } = stripeRecorder();
  await assertRejects(
    () => cancelWebSubscriptions("abc", { revenueCatKey: "rc", mode: "at_period_end", fetchImpl }),
    Error,
    "STRIPE_SECRET_KEY",
  );
});

// ---------------------------------------------------------------------------
// Which spelling of the id RevenueCat holds it under
// ---------------------------------------------------------------------------
//
// The two purchase channels disagree, and this function only ever asked one of them.
//
// iOS calls `Purchases.shared.logIn(userID.uuidString)`, and Swift uppercases — which is why every
// server-side lookup here and in `revenuecat-webhook` uppercases too. The website does not: it
// passes `session.user.id` straight to `Purchases.configure`/`changeUser`
// (site/src/lib/marketing/billing.ts, via PricingClient), and Supabase renders uuids lowercase. So a
// subscription bought on the website is attached to the LOWERCASE customer, and RevenueCat's
// app_user_id is case-sensitive.
//
// Asking under the wrong spelling is silent. `GET /v1/subscribers/{id}` creates the id it was asked
// about and answers 200 with empty maps rather than 404 — the whole premise of `isBlankSubscriber`
// in the webhook — so this function saw no subscriptions, reported 0 cancelled, and both callers
// read that as "nothing to cancel". The portal then said "Your subscription won't renew" and
// `delete-account` went ahead and deleted the account. Stripe kept billing in both cases, and after
// the second there is no account left to cancel from.
//
// Every test above passes "abc" as the id to a fake that answers any RevenueCat URL, which is why
// none of them could see this. These name the spelling.

/// RevenueCat as it actually behaves: the subscription exists under exactly one spelling, and any
/// other id comes back 200-with-nothing rather than 404.
function revenueCatHolding(
  heldUnderId: string,
  subscriptions: Record<string, unknown>,
): { askedFor: string[]; fetchImpl: typeof fetch } {
  const askedFor: string[] = [];
  const fetchImpl = ((url: string | URL) => {
    const href = String(url);
    if (href.includes("api.revenuecat.com")) {
      const id = decodeURIComponent(href.split("/subscribers/")[1]);
      askedFor.push(id);
      return Promise.resolve(
        new Response(
          JSON.stringify({ subscriber: { subscriptions: id === heldUnderId ? subscriptions : {} } }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    }
    return Promise.resolve(new Response("{}", { status: 200, headers: { "content-type": "application/json" } }));
  }) as typeof fetch;
  return { askedFor, fetchImpl };
}

const LOWER_ID = "f3318dc2-0000-4000-8000-00000000abcd";
const WEB_SUBSCRIPTION = {
  web_premium: { store: "rc_billing", expires_date: null, store_transaction_id: "sub_web" },
};

Deno.test("a subscription bought on the website is found and cancelled", async () => {
  const { askedFor, fetchImpl } = revenueCatHolding(LOWER_ID, WEB_SUBSCRIPTION);

  const cancelled = await cancelWebSubscriptions(LOWER_ID, {
    revenueCatKey: "rc",
    stripeKey: "sk",
    mode: "at_period_end",
    fetchImpl,
  });

  assertEquals(cancelled, 1, "a web subscription went uncancelled while the portal reported success");
  assertEquals(askedFor.includes(LOWER_ID), true, "the lowercase spelling was never asked about");
});

Deno.test("deleting an account still ends a website subscription", async () => {
  // The worse half of the same bug: a silent 0 here is not a failure, so deletion proceeds. There
  // is then no account, no portal and no way for the person to stop the charge themselves.
  const { fetchImpl } = revenueCatHolding(LOWER_ID, WEB_SUBSCRIPTION);

  const cancelled = await cancelWebSubscriptions(LOWER_ID, {
    revenueCatKey: "rc",
    stripeKey: "sk",
    mode: "immediately",
    fetchImpl,
  });

  assertEquals(cancelled, 1);
});

Deno.test("an App Store subscription held under the uppercase id is still nothing to cancel", async () => {
  // The direction that must not change. Looking under both spellings must not turn Apple's
  // subscription into something this tries to end through Stripe.
  const { fetchImpl } = revenueCatHolding(LOWER_ID.toUpperCase(), {
    ios_premium: { store: "app_store", expires_date: null, store_transaction_id: "1000" },
  });

  const cancelled = await cancelWebSubscriptions(LOWER_ID, {
    revenueCatKey: "rc",
    stripeKey: "sk",
    mode: "at_period_end",
    fetchImpl,
  });
  assertEquals(cancelled, 0);
});

Deno.test("one subscription found under both spellings is cancelled once", async () => {
  // Asking twice must not mean cancelling twice: the second Stripe call would be against a
  // subscription that is already gone, which throws, which reports a failure for a cancellation
  // that worked.
  const stripeCalls: string[] = [];
  const fetchImpl = ((url: string | URL) => {
    const href = String(url);
    if (href.includes("api.revenuecat.com")) {
      return Promise.resolve(
        new Response(
          JSON.stringify({ subscriber: { subscriptions: WEB_SUBSCRIPTION } }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    }
    if (href.includes("api.stripe.com/v1/subscriptions/")) stripeCalls.push(href);
    return Promise.resolve(new Response("{}", { status: 200, headers: { "content-type": "application/json" } }));
  }) as typeof fetch;

  const cancelled = await cancelWebSubscriptions(LOWER_ID, {
    revenueCatKey: "rc",
    stripeKey: "sk",
    mode: "at_period_end",
    fetchImpl,
  });

  assertEquals(cancelled, 1);
  assertEquals(stripeCalls.length, 1);
});
