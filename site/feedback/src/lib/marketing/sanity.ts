import { createClient } from "@sanity/client";
import type { PortableTextBlock } from "@portabletext/react";

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

export interface FaqItemDoc {
  question: string;
  answer: string;
  category: "getting-started" | "subscriptions" | "privacy";
  order?: number;
}

export async function getFaqItems(): Promise<FaqItemDoc[]> {
  return (
    (await sanityClient.fetch(
      `*[_type == "faqItem"] | order(order asc){ question, answer, category, order }`,
      {},
      { next: { revalidate: SANITY_REVALIDATE_SECONDS } }
    )) ?? []
  );
}

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
