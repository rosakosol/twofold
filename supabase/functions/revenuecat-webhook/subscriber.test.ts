// The decisions the webhook makes about a subscriber record.
//
// `resolveStartedAt` is the one with a real consequence attached: it decides which partner of two
// subscribers gets told to cancel. Getting it wrong doesn't lock anyone out — it asks the wrong
// person to stop paying for something they wanted.

import { assertEquals } from "jsr:@std/assert@1";
import {
  describeMissingStart,
  ENTITLEMENT_PLUS,
  ENTITLEMENT_PREMIUM,
  isEntitlementActive,
  resolveStartedAt,
  resolveTier,
  resolveWillRenew,
  type RestSubscriber,
} from "./subscriber.ts";

const NOW = Date.parse("2026-09-10T00:00:00Z");

Deno.test("an entitlement with a future expiry is active", () => {
  assertEquals(isEntitlementActive({ expires_date: "2026-12-01T00:00:00Z" }, NOW), true);
  assertEquals(isEntitlementActive({ expires_date: "2026-01-01T00:00:00Z" }, NOW), false);
});

// A billing issue Apple is still retrying. The SDK reports the entitlement active throughout, so
// treating it as lapsed here would cut off someone who is still being served.
Deno.test("a grace period keeps a lapsed entitlement active", () => {
  assertEquals(
    isEntitlementActive({ expires_date: "2026-09-01T00:00:00Z", grace_period_expires_date: "2026-09-20T00:00:00Z" }, NOW),
    true,
  );
});

// A lifetime grant, which has no expiry at all.
Deno.test("no expiry means active forever", () => {
  assertEquals(isEntitlementActive({ expires_date: null }, NOW), true);
  assertEquals(isEntitlementActive(undefined, NOW), false);
});

Deno.test("premium wins when both entitlements are somehow active", () => {
  const entitlements = {
    [ENTITLEMENT_PLUS]: { expires_date: "2026-12-01T00:00:00Z" },
    [ENTITLEMENT_PREMIUM]: { expires_date: "2026-12-01T00:00:00Z" },
  };
  assertEquals(resolveTier(entitlements, NOW), "premium");
});

Deno.test("an expired premium falls back to an active plus", () => {
  const entitlements = {
    [ENTITLEMENT_PLUS]: { expires_date: "2026-12-01T00:00:00Z" },
    [ENTITLEMENT_PREMIUM]: { expires_date: "2026-01-01T00:00:00Z" },
  };
  assertEquals(resolveTier(entitlements, NOW), "plus");
  assertEquals(resolveTier({}, NOW), null);
});

// MARK: - When the subscription was bought

/// A subscriber who bought an annual plan in March and has since renewed. This is the shape the
/// whole distinction rests on: `purchase_date` moved to the renewal, `original_purchase_date`
/// did not.
const renewedAnnual: RestSubscriber = {
  entitlements: {
    [ENTITLEMENT_PREMIUM]: {
      expires_date: "2027-03-01T00:00:00Z",
      purchase_date: "2026-03-01T00:00:00Z",
      product_identifier: "twofold_premium_yearly",
    },
  },
  subscriptions: {
    twofold_premium_yearly: {
      original_purchase_date: "2025-03-01T00:00:00Z",
      purchase_date: "2026-03-01T00:00:00Z",
    },
  },
};

Deno.test("the original purchase wins over the latest renewal", () => {
  assertEquals(resolveStartedAt(renewedAnnual, "premium"), "2025-03-01T00:00:00.000Z");
});

/// The reason it has to. Two partners, both subscribed: one has paid monthly for two years, the
/// other bought last month. Renewal dates would name the two-year subscriber as the newer one and
/// ask them to cancel.
Deno.test("a long-standing monthly subscriber is not mistaken for the newer one", () => {
  const monthlyForTwoYears: RestSubscriber = {
    entitlements: {
      [ENTITLEMENT_PLUS]: {
        expires_date: "2026-10-01T00:00:00Z",
        purchase_date: "2026-09-01T00:00:00Z",
        product_identifier: "twofold_plus_monthly",
      },
    },
    subscriptions: {
      twofold_plus_monthly: {
        original_purchase_date: "2024-09-01T00:00:00Z",
        purchase_date: "2026-09-01T00:00:00Z",
      },
    },
  };
  const boughtLastMonth: RestSubscriber = {
    entitlements: {
      [ENTITLEMENT_PLUS]: {
        expires_date: "2027-08-01T00:00:00Z",
        purchase_date: "2026-08-01T00:00:00Z",
        product_identifier: "twofold_plus_yearly",
      },
    },
    subscriptions: {
      twofold_plus_yearly: { original_purchase_date: "2026-08-01T00:00:00Z" },
    },
  };

  const older = resolveStartedAt(monthlyForTwoYears, "plus")!;
  const newer = resolveStartedAt(boughtLastMonth, "plus")!;
  assertEquals(
    older < newer,
    true,
    `the two-year subscriber (${older}) should predate the one who bought last month (${newer})`,
  );
});

Deno.test("the entitlement's own purchase date is the fallback", () => {
  const noSubscriptionsMap: RestSubscriber = {
    entitlements: {
      [ENTITLEMENT_PREMIUM]: {
        expires_date: "2027-03-01T00:00:00Z",
        purchase_date: "2026-03-01T00:00:00Z",
        product_identifier: "twofold_premium_yearly",
      },
    },
  };
  assertEquals(resolveStartedAt(noSubscriptionsMap, "premium"), "2026-03-01T00:00:00.000Z");
});

/// Null rather than a guess. The app can say "you're both subscribed" without naming anyone; it
/// cannot un-cancel a subscription someone was wrongly told to end.
Deno.test("an unreadable record yields no date rather than a guess", () => {
  assertEquals(resolveStartedAt({ entitlements: { [ENTITLEMENT_PREMIUM]: {} } }, "premium"), null);
  assertEquals(
    resolveStartedAt({ entitlements: { [ENTITLEMENT_PREMIUM]: { purchase_date: "not a date" } } }, "premium"),
    null,
  );
  assertEquals(resolveStartedAt({}, "premium"), null);
});

/// A lapsed subscription has no start. This is what clears the column when someone stops paying,
/// so an old date can't sit on the row and make them look like the later buyer forever.
Deno.test("no tier means no start date", () => {
  assertEquals(resolveStartedAt(renewedAnnual, null), null);
});

// MARK: - Whether it will renew

/// Cancelling does not end a subscription — it stops the renewal, and the entitlement runs to the
/// end of the paid period. That is why this exists separately from whether the tier is active:
/// without it, someone who cancels an annual plan keeps being told to cancel for another year.
Deno.test("a cancelled subscription is still active but will not renew", () => {
  const cancelled: RestSubscriber = {
    entitlements: {
      [ENTITLEMENT_PREMIUM]: {
        expires_date: "2027-03-01T00:00:00Z",
        product_identifier: "twofold_premium_yearly",
      },
    },
    subscriptions: {
      twofold_premium_yearly: { unsubscribe_detected_at: "2026-09-01T00:00:00Z" },
    },
  };
  assertEquals(resolveTier(cancelled.entitlements!, NOW), "premium", "still entitled");
  assertEquals(resolveWillRenew(cancelled, "premium"), false, "but not renewing");
});

Deno.test("a running subscription will renew", () => {
  assertEquals(resolveWillRenew(renewedAnnual, "premium"), true);
});

/// Absent is a real answer for a record RevenueCat does hold: it has seen no cancellation.
Deno.test("no unsubscribe field means it is still renewing", () => {
  const noField: RestSubscriber = {
    entitlements: { [ENTITLEMENT_PLUS]: { product_identifier: "twofold_plus_monthly" } },
    subscriptions: { twofold_plus_monthly: { original_purchase_date: "2026-01-01T00:00:00Z" } },
  };
  assertEquals(resolveWillRenew(noField, "plus"), true);
});

/// Null, not true. `redundant_subscription` reads unknown as "still renewing" so that a profile
/// the webhook hasn't seen since this shipped behaves exactly as it did before — that decision
/// lives in one place, and pre-empting it here would hide the distinction.
Deno.test("an unfindable subscription record is unknown, not a yes", () => {
  assertEquals(resolveWillRenew({ entitlements: { [ENTITLEMENT_PLUS]: {} } }, "plus"), null);
  assertEquals(
    resolveWillRenew(
      { entitlements: { [ENTITLEMENT_PLUS]: { product_identifier: "gone" } }, subscriptions: {} },
      "plus",
    ),
    null,
  );
  assertEquals(resolveWillRenew(renewedAnnual, null), null, "no tier, nothing to say");
});

// MARK: - The diagnostic

/// This string goes to a log line about a real person's subscription, so it carries field names
/// and product identifiers — shared constants, already in the app binary — and no dates.
///
/// The first version of this test asserted the product identifier was absent too, and failed:
/// `subscriptionKeys` is a list of them. Keeping them is the right call rather than the convenient
/// one, because the likeliest reason a date goes missing is the entitlement's `product_identifier`
/// not matching any key of `subscriptions`, and comparing those two lists is the whole diagnosis.
Deno.test("the missing-date diagnostic carries field names and no dates", () => {
  const described = describeMissingStart(renewedAnnual, "premium");
  assertEquals(described.includes("2025-03-01"), false, described);
  assertEquals(described.includes("2026-03-01"), false, described);
  assertEquals(described.includes("original_purchase_date"), true, described);
  // Both sides of the comparison that actually diagnoses a null.
  assertEquals(described.includes("productIdentifier=present"), true, described);
  assertEquals(described.includes("subscriptionKeys=[twofold_premium_yearly]"), true, described);
});
