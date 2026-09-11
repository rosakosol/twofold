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

// ---------------------------------------------------------------------------
// Live prices
// ---------------------------------------------------------------------------

/** What a package actually costs, as RevenueCat reports it for this buyer. */
export interface LivePrice {
  /** Already localised and currency-formatted by RevenueCat - "$9.99", "£7.99", "€8,99". */
  formattedPrice: string;
  /** $9.99 is 9990000. Used to derive the per-month and savings figures. */
  amountMicros: number;
  /** ISO 4217, for formatting figures we derive ourselves. */
  currency: string;
}

/** Keyed by the package identifier in config.ts's PLANS[..].monthly/yearly.packageId. */
export type LivePrices = Record<string, LivePrice>;

/**
 * Every price in the web offering, for display on the pricing cards.
 *
 * Called on mount with an anonymous app user id when nobody is signed in, because prices have
 * to be on screen well before anyone authenticates. RevenueCat treats the anonymous id as a
 * throwaway; the real purchase later runs under the Supabase user id via purchasePackage.
 *
 * Returns {} on any failure rather than throwing. Every caller falls back to the labels in
 * config.ts / Studio, so a RevenueCat outage costs the localised currency, not the page.
 */
export async function fetchLivePrices(appUserId: string): Promise<LivePrices> {
  const offering = await fetchOfferings(appUserId);
  if (!offering?.availablePackages) return {};

  const prices: LivePrices = {};
  for (const pkg of offering.availablePackages) {
    // `webBillingProduct` supersedes the deprecated `rcBillingProduct`; the SDK still
    // populates both, so fall back for older builds of the dependency.
    const product = pkg.webBillingProduct ?? pkg.rcBillingProduct;
    const price = product?.price;
    if (!price?.formattedPrice) continue;
    prices[pkg.identifier] = {
      formattedPrice: price.formattedPrice,
      amountMicros: price.amountMicros,
      currency: price.currency,
    };
  }
  return prices;
}

/** An anonymous id so the offering can be read before sign-in. */
export async function anonymousAppUserId(): Promise<string | null> {
  try {
    const { Purchases } = await import("@revenuecat/purchases-js");
    return Purchases.generateRevenueCatAnonymousAppUserId();
  } catch {
    return null;
  }
}
