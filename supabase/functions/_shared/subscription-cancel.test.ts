//
//  subscription-cancel.test.ts
//  _shared
//
//  The property under test is not "cancellation works". It is that this function never reports
//  success for a charge it did not stop.
//
//  That failure has happened here once already, and left no trace: the old code asked RevenueCat
//  about the uppercase spelling of a customer stored under the lowercase one, got a 200 with empty
//  maps rather than a 404, found nothing to cancel, and returned 0. The portal told the person their
//  subscription was cancelled, Stripe kept billing, and `delete-account` — which refuses to delete
//  only when this throws, and zero is not a throw — removed the account and with it the last way to
//  stop the charge.
//
//  So the tests that matter most here are the ones about *not* returning a number.
//

import { assertEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert@1";
import {
  cancelSubscription,
  cancelWebSubscriptions,
  isStoreManaged,
  listCustomerSubscriptions,
  partitionForCancellation,
  type Subscription,
} from "./subscription-cancel.ts";

const PROJECT = "proj123";
const KEY = "sk_test";
const USER = "f3318dc2-1111-2222-3333-444455556666";

function sub(overrides: Partial<Subscription> & { id: string }): Subscription {
  return { store: "rc_billing", gives_access: true, ...overrides };
}

// ---------------------------------------------------------------------------
// Which subscriptions are ours to end
// ---------------------------------------------------------------------------

Deno.test("Apple and Google subscriptions are the buyer's to cancel, not ours", () => {
  assertEquals(isStoreManaged("app_store"), true);
  assertEquals(isStoreManaged("play_store"), true);
  assertEquals(isStoreManaged("mac_app_store"), true);
  assertEquals(isStoreManaged("amazon"), true);
});

Deno.test("a promotional grant is not a charge, so not something to cancel", () => {
  assertEquals(isStoreManaged("promotional"), true);
});

Deno.test("RevenueCat Billing is ours to cancel", () => {
  assertEquals(isStoreManaged("rc_billing"), false);
});

Deno.test("an expired subscription is not put forward — it is billing nobody", () => {
  const { cancellable, storeManaged, unsupported } = partitionForCancellation([
    sub({ id: "s1", gives_access: false }),
  ]);
  assertEquals(cancellable.length, 0);
  assertEquals(storeManaged.length, 0);
  assertEquals(unsupported.length, 0);
});

Deno.test("only the web subscription is put forward for cancellation", () => {
  const { cancellable, storeManaged } = partitionForCancellation([
    sub({ id: "apple", store: "app_store" }),
    sub({ id: "web" }),
  ]);
  assertEquals(cancellable.map((s) => s.id), ["web"]);
  assertEquals(storeManaged.map((s) => s.id), ["apple"]);
});

/// Cancelling an already-cancelling subscription is asking RevenueCat to end something already
/// ending, which is how an idempotent path starts returning errors.
Deno.test("a subscription already set not to renew is left alone", () => {
  const { cancellable, unsupported } = partitionForCancellation([
    sub({ id: "s1", auto_renewal_status: "will_not_renew" }),
  ]);
  assertEquals(cancellable.length, 0);
  assertEquals(unsupported.length, 0);
});

/// The old Stripe web provider. RevenueCat's cancel endpoint is Web Billing only, so there is
/// nothing this can do about one — and silently counting it as nothing to do is the bug in the
/// header of this file.
Deno.test("a subscription on the old Stripe provider is unsupported, not ignored", () => {
  const { cancellable, storeManaged, unsupported } = partitionForCancellation([
    sub({ id: "legacy", store: "stripe" }),
  ]);
  assertEquals(cancellable.length, 0);
  assertEquals(storeManaged.length, 0);
  assertEquals(unsupported.map((s) => s.id), ["legacy"]);
});

// ---------------------------------------------------------------------------
// Talking to RevenueCat
// ---------------------------------------------------------------------------

function pageResponse(items: Subscription[], nextPage: string | null = null): Response {
  return new Response(JSON.stringify({ object: "list", items, next_page: nextPage }), { status: 200 });
}

Deno.test("an unknown customer id is no subscriptions rather than an error", async () => {
  const fetchImpl = (() => Promise.resolve(new Response("", { status: 404 }))) as unknown as typeof fetch;
  assertEquals(await listCustomerSubscriptions(PROJECT, "nobody", KEY, fetchImpl), []);
});

Deno.test("every page is followed, so a subscription cannot hide behind pagination", async () => {
  const seen: string[] = [];
  const fetchImpl = ((url: string) => {
    seen.push(url);
    return Promise.resolve(
      seen.length === 1
        ? pageResponse([sub({ id: "s1" })], "https://api.revenuecat.com/v2/next")
        : pageResponse([sub({ id: "s2" })]),
    );
  }) as unknown as typeof fetch;

  const subscriptions = await listCustomerSubscriptions(PROJECT, USER, KEY, fetchImpl);
  assertEquals(subscriptions.map((s) => s.id), ["s1", "s2"]);
  assertEquals(seen.length, 2);
});

Deno.test("a failed read throws rather than looking like an empty account", async () => {
  const fetchImpl = (() => Promise.resolve(new Response("", { status: 500 }))) as unknown as typeof fetch;
  await assertRejects(() => listCustomerSubscriptions(PROJECT, USER, KEY, fetchImpl));
});

Deno.test("cancelling posts to the cancel action, not the refund one", async () => {
  const calls: { url: string; method?: string }[] = [];
  const fetchImpl = ((url: string, init?: RequestInit) => {
    calls.push({ url, method: init?.method });
    return Promise.resolve(new Response("{}", { status: 200 }));
  }) as unknown as typeof fetch;

  await cancelSubscription(PROJECT, "sub_1", KEY, fetchImpl);
  assertEquals(calls.length, 1);
  assertEquals(calls[0].method, "POST");
  assertStringIncludes(calls[0].url, "/subscriptions/sub_1/actions/cancel");
});

Deno.test("cancelling twice succeeds, because this path is retried", async () => {
  const fetchImpl = (() => Promise.resolve(new Response("", { status: 404 }))) as unknown as typeof fetch;
  await cancelSubscription(PROJECT, "sub_1", KEY, fetchImpl);
});

Deno.test("a real cancel failure is surfaced, not swallowed", async () => {
  const fetchImpl = (() => Promise.resolve(new Response("", { status: 500 }))) as unknown as typeof fetch;
  await assertRejects(() => cancelSubscription(PROJECT, "sub_1", KEY, fetchImpl));
});

// ---------------------------------------------------------------------------
// The whole operation
// ---------------------------------------------------------------------------

/// Routes list calls by the customer id in the URL, so a test can say "this person exists under the
/// uppercase spelling and not the lowercase one" — the split that caused the original bug.
function stubFor(byCustomer: Record<string, Subscription[]>, cancelled: string[]) {
  return ((url: string, init?: RequestInit) => {
    if (init?.method === "POST") {
      cancelled.push(url.split("/subscriptions/")[1].replace("/actions/cancel", ""));
      return Promise.resolve(new Response("{}", { status: 200 }));
    }
    const customer = decodeURIComponent(url.split("/customers/")[1].split("/")[0]);
    const items = byCustomer[customer];
    return Promise.resolve(items ? pageResponse(items) : new Response("", { status: 404 }));
  }) as unknown as typeof fetch;
}

Deno.test("the customer is found under the uppercase spelling the app signs in with", async () => {
  const cancelled: string[] = [];
  const count = await cancelWebSubscriptions(USER, {
    projectId: PROJECT,
    revenueCatKey: KEY,
    fetchImpl: stubFor({ [USER.toUpperCase()]: [sub({ id: "s1" })] }, cancelled),
  });
  assertEquals(count, 1);
  assertEquals(cancelled, ["s1"]);
});

/// The website bought under the lowercase form before the two were reconciled, so those customers
/// exist and are the ones most likely to need cancelling by somebody who cannot do it themselves.
Deno.test("the customer is found under the lowercase spelling the website bought with", async () => {
  const cancelled: string[] = [];
  const count = await cancelWebSubscriptions(USER, {
    projectId: PROJECT,
    revenueCatKey: KEY,
    fetchImpl: stubFor({ [USER.toLowerCase()]: [sub({ id: "s1" })] }, cancelled),
  });
  assertEquals(count, 1);
  assertEquals(cancelled, ["s1"]);
});

Deno.test("one subscription answering to both spellings is cancelled once", async () => {
  const cancelled: string[] = [];
  const both = [sub({ id: "s1" })];
  const count = await cancelWebSubscriptions(USER, {
    projectId: PROJECT,
    revenueCatKey: KEY,
    fetchImpl: stubFor({ [USER.toUpperCase()]: both, [USER.toLowerCase()]: both }, cancelled),
  });
  assertEquals(count, 1);
  assertEquals(cancelled, ["s1"]);
});

Deno.test("an App Store subscription is reported as nothing to cancel, not as a failure", async () => {
  const cancelled: string[] = [];
  const count = await cancelWebSubscriptions(USER, {
    projectId: PROJECT,
    revenueCatKey: KEY,
    fetchImpl: stubFor({ [USER.toUpperCase()]: [sub({ id: "apple", store: "app_store" })] }, cancelled),
  });
  assertEquals(count, 0);
  assertEquals(cancelled, []);
});

/// The one this file exists for. A subscription nothing here can stop must never be counted as
/// nothing to do — `delete-account` refuses to delete only when this throws.
Deno.test("a legacy Stripe subscription throws rather than reporting success", async () => {
  const cancelled: string[] = [];
  await assertRejects(
    () =>
      cancelWebSubscriptions(USER, {
        projectId: PROJECT,
        revenueCatKey: KEY,
        fetchImpl: stubFor({ [USER.toUpperCase()]: [sub({ id: "legacy", store: "stripe" })] }, cancelled),
      }),
    Error,
    "stripe",
  );
  assertEquals(cancelled, []);
});

/// Raising before cancelling anything, so a mixed set cannot half-succeed and return a number that
/// implies the rest were dealt with.
Deno.test("a mixed set cancels nothing rather than some of it", async () => {
  const cancelled: string[] = [];
  await assertRejects(() =>
    cancelWebSubscriptions(USER, {
      projectId: PROJECT,
      revenueCatKey: KEY,
      fetchImpl: stubFor(
        { [USER.toUpperCase()]: [sub({ id: "web" }), sub({ id: "legacy", store: "stripe" })] },
        cancelled,
      ),
    })
  );
  assertEquals(cancelled, []);
});

Deno.test("an account with nothing at all cancels nothing and does not fail", async () => {
  const cancelled: string[] = [];
  const count = await cancelWebSubscriptions(USER, {
    projectId: PROJECT,
    revenueCatKey: KEY,
    fetchImpl: stubFor({}, cancelled),
  });
  assertEquals(count, 0);
});
