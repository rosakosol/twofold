import { createClient } from "@sanity/client";
import type { PortableTextBlock } from "@portabletext/react";
import { PLANS, type PlanId } from "@/lib/marketing/config";

// Server-side Sanity reads for marketing content (hero, features, FAQ, legal pages).
// Replaces the old hand-rolled client-side fetch (site/assets/js/cms.js) — moving this
// server-side (RSC, with revalidation) fixes the old "flash of fallback copy, then CMS
// content swaps in" UX for free, since the real content is already in the HTML on
// first paint.
export const sanityClient = createClient({
  projectId: process.env.NEXT_PUBLIC_SANITY_PROJECT_ID,
  dataset: process.env.NEXT_PUBLIC_SANITY_DATASET,
  apiVersion: process.env.NEXT_PUBLIC_SANITY_API_VERSION ?? "2024-01-01",
  useCdn: true,
  // Revalidated on a timer rather than per-request — marketing copy changes rarely,
  // and this keeps every page a fast cached fetch instead of hitting Sanity on every
  // request. 60s matches a reasonable "edit in Studio, see it live within a minute"
  // expectation without needing to wire up on-demand revalidation webhooks yet.
  stega: false,
});

export const SANITY_REVALIDATE_SECONDS = 60;

export interface HeroDoc {
  eyebrow?: string;
  headline?: string;
  subtext?: string;
  heroNote?: string;
}

export async function getHero(): Promise<HeroDoc | null> {
  return sanityClient.fetch(
    `*[_id == "hero"][0]{ eyebrow, headline, subtext, heroNote }`,
    {},
    { next: { revalidate: SANITY_REVALIDATE_SECONDS } }
  );
}

export interface FeatureDoc {
  title?: string;
  teaserDescription?: string;
  detailDescription?: string;
  bullets?: string[];
}

export async function getFeature(slug: string): Promise<FeatureDoc | null> {
  return sanityClient.fetch(
    `*[_id == $id][0]{ title, teaserDescription, detailDescription, bullets }`,
    { id: `feature-${slug}` },
    { next: { revalidate: SANITY_REVALIDATE_SECONDS } }
  );
}

export async function getFeatures(slugs: readonly string[]): Promise<Record<string, FeatureDoc>> {
  const ids = slugs.map((slug) => `feature-${slug}`);
  const docs: (FeatureDoc & { _id: string })[] = await sanityClient.fetch(
    `*[_id in $ids]{ _id, title, teaserDescription, detailDescription, bullets }`,
    { ids },
    { next: { revalidate: SANITY_REVALIDATE_SECONDS } }
  );
  const bySlug: Record<string, FeatureDoc> = {};
  for (const doc of docs) {
    const slug = doc._id.replace(/^feature-/, "");
    bySlug[slug] = doc;
  }
  return bySlug;
}

// FAQ used to be fetched from here (getFaqItems/FaqItemDoc) — retired along with Sanity's
// `faqItem` document type. See src/lib/marketing/faq.ts (Supabase-backed) instead.

export interface LegalPageDoc {
  title?: string;
  lastUpdated?: string;
  noticeText?: string;
  body?: PortableTextBlock[];
}

export async function getLegalPage(pageId: "privacy" | "terms"): Promise<LegalPageDoc | null> {
  return sanityClient.fetch(
    `*[_id == $id][0]{ title, lastUpdated, noticeText, body }`,
    { id: `legalPage-${pageId}` },
    { next: { revalidate: SANITY_REVALIDATE_SECONDS } }
  );
}

// Pricing plans. Sanity holds DISPLAY copy only (name, tagline, price labels, features,
// which card is featured); the RevenueCat wiring (entitlement + package IDs) always comes
// from code (config.ts PLANS), which also supplies the fallback for any field left blank
// in Studio — same null-fallback philosophy as getHero. getResolvedPlans() merges the two
// so both the /pricing cards and the home pricing preview render the same edited content.
export interface PlanDoc {
  name?: string;
  tagline?: string;
  featured?: boolean;
  monthlyPriceLabel?: string;
  yearlyPriceLabel?: string;
  yearlyPerMonthLabel?: string;
  ctaLabel?: string;
  features?: string[];
}

export interface ResolvedPlan {
  id: PlanId;
  name: string;
  tagline: string;
  featured: boolean;
  ctaLabel: string;
  monthly: { priceLabel: string };
  yearly: { priceLabel: string; perMonthLabel: string };
  features: string[];
}

type PlanDocWithMeta = PlanDoc & { _id: string; _updatedAt?: string };

export async function getPlans(): Promise<{ plus: PlanDocWithMeta | null; premium: PlanDocWithMeta | null }> {
  const docs: PlanDocWithMeta[] = await sanityClient.fetch(
    `*[_id in ["plan-plus", "plan-premium"]]{ _id, _updatedAt, name, tagline, featured, monthlyPriceLabel, yearlyPriceLabel, yearlyPerMonthLabel, ctaLabel, features }`,
    {},
    { next: { revalidate: SANITY_REVALIDATE_SECONDS } }
  );
  return {
    plus: docs.find((d) => d._id === "plan-plus") ?? null,
    premium: docs.find((d) => d._id === "plan-premium") ?? null,
  };
}

function resolvePlan(id: PlanId, doc: PlanDoc | null, featuredDefault: boolean): ResolvedPlan {
  const code = PLANS[id];
  return {
    id,
    name: doc?.name || code.name,
    tagline: doc?.tagline || code.tagline,
    featured: doc?.featured ?? featuredDefault,
    ctaLabel: doc?.ctaLabel || `Get ${id === "plus" ? "Plus" : "Premium"}`,
    monthly: { priceLabel: doc?.monthlyPriceLabel || code.monthly.priceLabel },
    yearly: {
      priceLabel: doc?.yearlyPriceLabel || code.yearly.priceLabel,
      perMonthLabel: doc?.yearlyPerMonthLabel || code.yearly.perMonthLabel || code.yearly.priceLabel,
    },
    features: doc?.features?.length ? doc.features : code.features,
  };
}

export async function getResolvedPlans(): Promise<{ plus: ResolvedPlan; premium: ResolvedPlan }> {
  const { plus, premium } = await getPlans();
  const resolvedPlus = resolvePlan("plus", plus, false);
  const resolvedPremium = resolvePlan("premium", premium, true);

  // Guard: at most one plan may be featured (the "Most popular" badge + highlight). An
  // editor can set the flag on both docs independently, which would show two badges — so
  // if both are on, last edited wins and the other is quietly demoted. Uses Sanity's
  // _updatedAt; a missing/unparseable stamp sorts oldest so a real edit always beats it.
  if (resolvedPlus.featured && resolvedPremium.featured) {
    const plusEdited = Date.parse(plus?._updatedAt ?? "") || 0;
    const premiumEdited = Date.parse(premium?._updatedAt ?? "") || 0;
    if (plusEdited >= premiumEdited) {
      resolvedPremium.featured = false;
    } else {
      resolvedPlus.featured = false;
    }
  }

  return { plus: resolvedPlus, premium: resolvedPremium };
}

export interface QuizQuestionDoc {
  question: string;
  order: number;
  options: { label: string; lean: "strong_plus" | "plus" | "neutral" | "premium" | "strong_premium" }[];
}

export async function getQuizQuestions(): Promise<QuizQuestionDoc[]> {
  return (
    (await sanityClient.fetch(
      `*[_type == "quizQuestion"] | order(order asc){ question, order, options }`,
      {},
      { next: { revalidate: SANITY_REVALIDATE_SECONDS } }
    )) ?? []
  );
}

export interface QuizResultDoc {
  title: string;
  description: string;
  ctaLabel: string;
}

export async function getQuizResults(): Promise<{ plus: QuizResultDoc | null; premium: QuizResultDoc | null }> {
  const docs: (QuizResultDoc & { _id: string })[] = await sanityClient.fetch(
    `*[_id in ["quizResult-plus", "quizResult-premium"]]{ _id, title, description, ctaLabel }`,
    {},
    { next: { revalidate: SANITY_REVALIDATE_SECONDS } }
  );
  return {
    plus: docs.find((d) => d._id === "quizResult-plus") ?? null,
    premium: docs.find((d) => d._id === "quizResult-premium") ?? null,
  };
}
