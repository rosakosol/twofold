// Twofold — marketing-site config, ported from the old static site's
// assets/js/config.js. Genuinely static, non-secret data (plan copy, entitlement ids)
// stays as plain exports; anything environment-specific (API keys, Sanity project)
// moved to env vars instead of being hardcoded in source — see .env.local.example.

export const APP_STORE_URL = "https://apps.apple.com/app/id6789054723";

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

// An offering for people who have subscribed before, whose packages carry no free trial. Null
// until one exists in the RevenueCat dashboard - do not set it to an id that is not there.
//
// Only needed if RevenueCat's own trial eligibility does not already stop a second trial: the
// products in WEB_OFFERING_ID should be set to "Didn't have any subscription yet", which covers App
// Store and web history under one customer. What that cannot see is the web customers created under
// the old lowercase app user id (see `revenueCatAppUserId` in billing.ts), which RevenueCat treats
// as a different person. When set, checkout and the live prices read this offering instead for
// anyone `resolveTrialStanding` calls returning. Its packages must use the same identifiers as
// PLANS below (`plus_monthly` and so on), because that is how `findPackage` finds them.
export const RETURNING_CUSTOMER_OFFERING_ID: string | null = null;

// Package identifiers within WEB_OFFERING_ID, and they must match the dashboard exactly —
// `findPackage` looks packages up by this string, and a miss is silent: `pkg` comes back null and
// the page shows its "web checkout is being finalized" card instead of a checkout.
//
// These were the packages' display names ("Twofold Plus Monthly"), which is what the dashboard
// generated when they were first created against the Stripe provider. They were recreated under
// RevenueCat Billing with these identifiers instead. RevenueCat does not allow renaming a package
// identifier after creation, so recreating the packages is the only way to change them, and these
// four values are the other half of that change.
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
    monthly: { packageId: "plus_monthly", price: 9.99, priceLabel: "$9.99" },
    yearly: { packageId: "plus_yearly", price: 59.99, priceLabel: "$59.99", perMonthLabel: "$5.00" },
    features: [
      "Everything you need for long-distance love",
      "Unlimited trips & memories",
      "Track 2 flights live each month",
      "Save unlimited flights to your trips",
      "500+ questions and conversation starters",
      "Sudoku and Word Guess",
      "Home Screen & Lock Screen widgets",
    ],
  },
  premium: {
    id: "premium",
    name: "Twofold Premium",
    entitlement: ENTITLEMENTS.premium,
    tagline: "The full relationship globe experience",
    monthly: { packageId: "premium_monthly", price: 19.99, priceLabel: "$19.99" },
    yearly: { packageId: "premium_yearly", price: 119.99, priceLabel: "$119.99", perMonthLabel: "$10.00" },
    features: [
      "Everything in Twofold Plus",
      "Track 5 flights live each month",
      "2000+ questions, including premium decks",
      "Word Search and Connect 4",
      "Every Sudoku difficulty, and Word Guess with no daily limit",
      "Flight delay analysis, gate & aircraft details",
      "Your Relationship Record, exported as a keepsake",
      "A monthly streak repair",
      "Smart Rotating widget, and Drawing Pad and Time & Weather at Medium size",
    ],
  },
};

// FEATURE_SLUGS/FeatureSlug used to live here, back when the feature cards were a fixed
// set of six slots. Features are now a free-form Sanity list (add/remove/rename/reorder
// in Studio), so the list and its order come from the CMS — see
// src/lib/marketing/featuresFallback.ts for the cold-start fallback copy.
