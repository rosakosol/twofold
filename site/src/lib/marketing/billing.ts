"use client";

import { WEB_OFFERING_ID } from "@/lib/marketing/config";
import type { Purchases, Offering, Package, CustomerInfo } from "@revenuecat/purchases-js";

// Thin RevenueCat Web Billing wrapper — port of the old site's billing.js. Never talks
// to Stripe directly: RevenueCat's Web SDK opens a RevenueCat-hosted checkout backed by
// whichever Stripe account is connected in the RC dashboard, and grants the resulting
// entitlement to `appUserId` (the Supabase user id) server-side — the iOS app sees the
// same entitlement next time it fetches CustomerInfo, no webhook needed on our side.
//
// The SDK is dynamically imported (not a static import) so it's only ever pulled into
// the bundle when the pricing page actually mounts it, same as the original.

let purchasesPromise: Promise<Purchases | null> | null = null;

function apiKey(): string | undefined {
  return process.env.NEXT_PUBLIC_REVENUECAT_WEB_BILLING_API_KEY;
}

function isConfigured(): boolean {
  const key = apiKey();
  return Boolean(key && !key.includes("TODO"));
}

/** Configures (once) and returns the shared Purchases instance, or null if unavailable. */
export async function getPurchases(appUserId: string): Promise<Purchases | null> {
  if (!isConfigured()) return null;
  if (purchasesPromise) return purchasesPromise;

  purchasesPromise = (async () => {
    try {
      const { Purchases } = await import("@revenuecat/purchases-js");
      return Purchases.configure({ apiKey: apiKey()!, appUserId });
    } catch (err) {
      console.warn("[twofold] RevenueCat Web Billing unavailable", err);
      return null;
    }
  })();

  return purchasesPromise;
}

/** Returns the web offering (or RevenueCat's "current" as a fallback), or null if unavailable. */
export async function fetchOfferings(appUserId: string): Promise<Offering | null> {
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

export async function fetchCustomerInfo(appUserId: string): Promise<CustomerInfo | null> {
  const purchases = await getPurchases(appUserId);
  if (!purchases) return null;
  try {
    return await purchases.getCustomerInfo();
  } catch (err) {
    console.warn("[twofold] getCustomerInfo failed", err);
    return null;
  }
}

/** Finds a package by its dashboard identifier (see config.ts PLANS[..].monthly/yearly.packageId). */
export function findPackage(offering: Offering | null, packageId: string): Package | null {
  if (!offering?.availablePackages) return null;
  return offering.availablePackages.find((p) => p.identifier === packageId) ?? null;
}

export async function purchasePackage(appUserId: string, rcPackage: Package) {
  const purchases = await getPurchases(appUserId);
  if (!purchases) throw new Error("Web checkout isn't available yet.");
  return purchases.purchase({ rcPackage });
}

export function activeEntitlements(customerInfo: CustomerInfo | null): string[] {
  return customerInfo ? Object.keys(customerInfo.entitlements?.active ?? {}) : [];
}
