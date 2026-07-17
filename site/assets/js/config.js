// Twofold — shared site config
//
// Everything in this file is public/client-side by design (anon keys scoped by RLS,
// publishable billing keys) — nothing secret lives here. Values marked TODO are
// placeholders; see site/README.md "Go-live checklist" for exactly what to replace
// them with and where each one comes from.

export const APP_STORE_URL = "https://apps.apple.com/app/id0000000000"; // TODO: real App Store id once listed

// Sanity CMS (marketing copy: hero text, feature copy, FAQ entries, legal page bodies).
// Project ID is public/non-secret by design — reads go straight to Sanity's CDN API
// from the browser, no server or token needed, as long as the "production" dataset is
// set to Public visibility and this site's origin is added under Sanity project
// settings → API → CORS origins (see site/README.md "CMS setup").
export const SANITY_PROJECT_ID = "fck477cu";
export const SANITY_DATASET = "production";
export const SANITY_API_VERSION = "2024-01-01";

export const SUPABASE_URL = "https://ipfzswswwukfqphloojo.supabase.co";
export const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_KvH6r2_haPL1sbAc1d4F-Q_5l1ImkpK";

// RevenueCat Web Billing (RevenueCat Billing, powered by Stripe). Create this key in
// the RevenueCat dashboard → Project settings → API keys → "Web Billing" public key,
// *after* connecting Stripe under Web → Billing. It is safe to expose client-side —
// same trust model as the app's RevenueCat public SDK key.
export const REVENUECAT_WEB_BILLING_API_KEY = "strp_sb_tBLcehpzrbeIUvuBvYnWOMWj";

// Mirrors Twofold/Twofold/Services/RevenueCatConfig.swift — same entitlement identifiers
// the iOS app already checks, so a web purchase unlocks the app instantly with no extra
// mapping. Do not rename these without renaming them in RevenueCatConfig.swift too.
export const ENTITLEMENTS = {
  plus: "Twofold Plus",
  premium: "Twofold Premium",
};

// The Offering identifier (RevenueCat dashboard → Product catalog → Offerings) that
// groups the four Web Billing packages below.
export const WEB_OFFERING_ID = "web_default"; // confirmed against the live dashboard

// Package identifiers within WEB_OFFERING_ID. These are RevenueCat's own package
// identifiers — RevenueCat doesn't allow renaming a package's identifier after
// creation, so rather than fight that, these match whatever the dashboard actually
// generated (its display name, in this case) instead of a short code we'd have
// preferred. If you ever recreate these packages with cleaner identifiers, update the
// four values below to match.
export const PLANS = {
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
