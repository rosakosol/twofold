// The classification is the load-bearing part: get it wrong towards "store managed" and a web
// subscriber keeps being charged after deleting their account, get it wrong the other way and
// deletion fails for every App Store subscriber because there is nothing we can cancel.

import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  activeSubscriptions,
  cancellableSubscriptions,
  cancelStripeSubscription,
  isStoreManaged,
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
