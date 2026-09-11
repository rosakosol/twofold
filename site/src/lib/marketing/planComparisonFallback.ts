import type { PlanComparisonDoc } from "@/lib/marketing/sanity";

export interface ComparisonRow {
  label: string;
  /** Empty string means "not included" and renders as a dash. */
  plus: string;
  premium: string;
}

export interface ResolvedPlanComparison {
  heading: string;
  intro: string;
  rows: ComparisonRow[];
}

// Cold-start copy for the `planComparison` singleton, in the same spirit as
// FEATURES_FALLBACK: what /pricing shows before anything is published in Studio.
//
// The numbers here are the ones already quoted in PLANS (config.ts) and on the plan
// documents, so the table can't contradict the cards above it on a fresh dataset. Once the
// document exists, Studio owns every row and this is only ever the safety net.
export const PLAN_COMPARISON_FALLBACK: ResolvedPlanComparison = {
  heading: "Compare the plans",
  intro: "Both plans cover the essentials. Premium is for couples who want the full picture.",
  rows: [
    { label: "Trips & memories", plus: "Unlimited", premium: "Unlimited" },
    { label: "Live-tracked flights each month", plus: "2", premium: "5" },
    // The limit is on tracking, not on flights. Without this row "2" reads as a cap on how much of
    // their own travel a couple may record, which is not what happens and is a far meaner promise
    // than the one being made.
    { label: "Flights saved to your trips", plus: "Unlimited", premium: "Unlimited" },
    { label: "Questions & games", plus: "500+", premium: "2000+" },
    { label: "Home & Lock Screen widgets", plus: "Yes", premium: "Yes" },
    { label: "Live Activities for in-progress flights", plus: "Yes", premium: "Yes" },
    { label: "Interactive 3D globe", plus: "Yes", premium: "Yes" },
    { label: "Premium widget styles", plus: "", premium: "Yes" },
  ],
};

/**
 * Merges the Sanity document over the fallback. A missing document, or one with no rows,
 * falls back wholesale — a half-filled table is worse than the known-good one, and an editor
 * clearing every row is far more likely to be a mistake than an instruction.
 */
export function resolvePlanComparison(doc: PlanComparisonDoc | null): ResolvedPlanComparison {
  if (!doc?.rows?.length) return PLAN_COMPARISON_FALLBACK;

  return {
    heading: doc.heading || PLAN_COMPARISON_FALLBACK.heading,
    intro: doc.intro || PLAN_COMPARISON_FALLBACK.intro,
    rows: doc.rows
      .filter((row) => row.label)
      .map((row) => ({
        label: row.label as string,
        plus: row.plus ?? "",
        premium: row.premium ?? "",
      })),
  };
}
