// Twofold — marketing-site config, ported from the old static site's
// assets/js/config.js. Genuinely static, non-secret data (plan copy, entitlement ids)
// stays as plain exports; anything environment-specific (API keys, Sanity project)
// moved to env vars instead of being hardcoded in source — see .env.local.example.

export const APP_STORE_URL = "https://apps.apple.com/app/id0000000000"; // TODO: real App Store id once listed

// Mirrors Twofold/Twofold/Services/RevenueCatConfig.swift — same entitlement
// identifiers the iOS app already checks, so a web purchase unlocks the app instantly
// with no extra mapping. Do not rename these without renaming them there too.
export const ENTITLEMENTS = {
  plus: "Twofold Plus",
  premium: "Twofold Premium",
} as const;

// The Offering identifier (RevenueCat dashboard -> Product catalog -> Offerings) that
// groups the four Web Billing packages below.
export const WEB_OFFERING_ID = "web_default";

// Package identifiers within WEB_OFFERING_ID. These are RevenueCat's own package
// identifiers — RevenueCat doesn't allow renaming a package's identifier after
// creation, so these match whatever the dashboard actually generated (its display
// name, in this case). If you ever recreate these packages with cleaner identifiers,
// update the four values below to match.
export interface PlanPeriod {
  packageId: string;
  price: number;
  priceLabel: string;
  perMonthLabel?: string;
}

export type PlanId = "plus" | "premium";

export interface Plan {
  id: PlanId;
  name: string;
  entitlement: string;
  tagline: string;
  monthly: PlanPeriod;
  yearly: PlanPeriod;
  features: string[];
}

export const PLANS: Record<"plus" | "premium", Plan> = {
  plus: {
    id: "plus",
    name: "Twofold Plus",
    entitlement: ENTITLEMENTS.plus,
    tagline: "Everything you need for long-distance love",
    monthly: { packageId: "Twofold Plus Monthly", price: 9.99, priceLabel: "$9.99" },
    yearly: { packageId: "Twofold Plus Yearly", price: 59.99, priceLabel: "$59.99", perMonthLabel: "$5.00" },
    features: [
      "Everything you need for long-distance love",
      "Unlimited trips & memories",
      "Track up to 5 flights each month",
      "500+ questions and games",
      "Home Screen & Lock Screen widgets",
    ],
  },
  premium: {
    id: "premium",
    name: "Twofold Premium",
    entitlement: ENTITLEMENTS.premium,
    tagline: "The full relationship globe experience",
    monthly: { packageId: "Twofold Premium Monthly", price: 19.99, priceLabel: "$19.99" },
    yearly: { packageId: "Twofold Premium Yearly", price: 119.99, priceLabel: "$119.99", perMonthLabel: "$10.00" },
    features: [
      "Everything in Twofold Plus",
      "Track up to 20 flights each month",
      "2000+ questions and games",
      "Interactive 3D globe & premium widgets",
      "Relationship Record PDF export",
    ],
  },
};

export const FEATURE_SLUGS = [
  "relationship-globe",
  "live-flight-tracking",
  "memories",
  "couple-games",
  "widgets-live-activities",
  "relationship-record",
] as const;

export type FeatureSlug = (typeof FEATURE_SLUGS)[number];
