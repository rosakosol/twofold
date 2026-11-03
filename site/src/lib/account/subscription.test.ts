import { describe, expect, it } from "vitest";
import { cancellability } from "@/lib/console/accountDetail";
import { deletionBillingWarning, subscriptionControl, type SubscriptionSnapshot } from "./subscription";

function snapshot(store: string | null, active = true): SubscriptionSnapshot {
  return { active, tier: "plus", store, willRenew: true, startedAt: null, isTrial: null, expiresAt: null };
}

const STORES = [null, "", "stripe", "rc_billing", "promotional", "app_store", "mac_app_store", "play_store", "a_future_store"];

describe("subscriptionControl", () => {
  it.each([
    [null, "unknown"],
    ["", "unknown"],
    ["  ", "unknown"],
    ["stripe", "web"],
    ["RC_Billing", "web"],
    ["promotional", "grant"],
    ["app_store", "elsewhere"],
    ["play_store", "elsewhere"],
    ["a_future_store", "unknown"],
  ])("classifies store %j as %s", (store, kind) => {
    expect(subscriptionControl(snapshot(store)).kind).toBe(kind);
  });

  it("has nothing to manage without an active subscription", () => {
    for (const store of STORES) expect(subscriptionControl(snapshot(store, false)).kind).toBe("none");
  });
});

describe("deletionBillingWarning", () => {
  it("warns that deleting won't cancel a subscription an app store bills for", () => {
    expect(deletionBillingWarning(snapshot("app_store"))).toBe("store");
    expect(deletionBillingWarning(snapshot("play_store"))).toBe("store");
  });

  it("doesn't tell somebody on a promotional grant to cancel in an app store", () => {
    expect(deletionBillingWarning(snapshot("promotional"))).toBeNull();
  });

  it("doesn't claim an unrecorded or unrecognised store is an app store", () => {
    expect(deletionBillingWarning(snapshot(null))).toBe("unknown");
    expect(deletionBillingWarning(snapshot(""))).toBe("unknown");
    expect(deletionBillingWarning(snapshot("a_future_store"))).toBe("unknown");
  });

  it("needs no warning for a website subscription or none at all", () => {
    expect(deletionBillingWarning(snapshot("stripe"))).toBeNull();
    expect(deletionBillingWarning(snapshot("rc_billing"))).toBeNull();
    for (const store of STORES) expect(deletionBillingWarning(snapshot(store, false))).toBeNull();
  });
});

describe("cancellability (console)", () => {
  it("agrees with the portal on what is ours to cancel", () => {
    for (const store of STORES) {
      for (const active of [true, false]) {
        expect(cancellability(store, active).ours).toBe(subscriptionControl(snapshot(store, active)).kind === "web");
      }
    }
  });
});
