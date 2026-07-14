// Twofold — thin RevenueCat Web Billing (RevenueCat Billing, powered by Stripe) wrapper.
//
// This never talks to Stripe directly — RevenueCat's Web SDK opens a RevenueCat-hosted
// checkout backed by whichever Stripe account is connected in the RC dashboard, and
// grants the resulting entitlement to `appUserId` server-side. The iOS app (same
// appUserId, via Supabase user id) sees the same entitlement the next time it fetches
// CustomerInfo — no webhook or server code needed on our side for the purchase itself.
//
// REVENUECAT_WEB_BILLING_API_KEY is a placeholder until Web Billing + Stripe are
// connected in the RevenueCat dashboard (see README). Every call here is wrapped so the
// rest of the page can render normally and fall back to "buy on the App Store" if the
// SDK isn't live yet, instead of throwing.

import { REVENUECAT_WEB_BILLING_API_KEY, WEB_OFFERING_ID } from "/assets/js/config.js";

let purchasesPromise = null;

function isPlaceholderKey() {
  return !REVENUECAT_WEB_BILLING_API_KEY || REVENUECAT_WEB_BILLING_API_KEY.includes("TODO");
}

/** Configures (once) and returns the shared Purchases instance, or null if unavailable. */
export async function getPurchases(appUserId) {
  if (isPlaceholderKey()) return null;
  if (purchasesPromise) return purchasesPromise;

  purchasesPromise = (async () => {
    try {
      const { Purchases } = await import("https://esm.sh/@revenuecat/purchases-js@1");
      return Purchases.configure({ apiKey: REVENUECAT_WEB_BILLING_API_KEY, appUserId });
    } catch (err) {
      console.warn("[twofold] RevenueCat Web Billing unavailable", err);
      return null;
    }
  })();

  return purchasesPromise;
}

/** Returns { current: { availablePackages: [...] } } or null if the SDK/offering isn't available. */
export async function fetchOfferings(appUserId) {
  const purchases = await getPurchases(appUserId);
  if (!purchases) return null;
  try {
    const offerings = await purchases.getOfferings();
    return offerings?.all?.[WEB_OFFERING_ID] ?? offerings?.current ?? null;
  } catch (err) {
    console.warn("[twofold] getOfferings failed", err);
    return null;
  }
}

export async function fetchCustomerInfo(appUserId) {
  const purchases = await getPurchases(appUserId);
  if (!purchases) return null;
  try {
    return await purchases.getCustomerInfo();
  } catch (err) {
    console.warn("[twofold] getCustomerInfo failed", err);
    return null;
  }
}

/** Finds a package by its dashboard identifier (see config.js PLANS[..].monthly/yearly.packageId). */
export function findPackage(offering, packageId) {
  if (!offering?.availablePackages) return null;
  return offering.availablePackages.find((p) => p.identifier === packageId) ?? null;
}

export async function purchasePackage(appUserId, rcPackage) {
  const purchases = await getPurchases(appUserId);
  if (!purchases) throw new Error("Web checkout isn't available yet.");
  return purchases.purchase({ rcPackage });
}

export function activeEntitlements(customerInfo) {
  return customerInfo ? Object.keys(customerInfo.entitlements?.active ?? {}) : [];
}
