import type { Metadata } from "next";
import { PricingClient } from "@/components/marketing/PricingClient";
import { getPlanComparison, getResolvedPlans } from "@/lib/marketing/sanity";
import { resolvePlanComparison } from "@/lib/marketing/planComparisonFallback";

export const metadata: Metadata = {
  title: "Pricing",
  description: "Twofold Plus and Premium pricing. Subscribe on the web or in the app - either partner's subscription unlocks it for both of you.",
};

export default async function PricingPage() {
  const [plans, comparisonDoc] = await Promise.all([getResolvedPlans(), getPlanComparison()]);
  return <PricingClient plans={plans} comparison={resolvePlanComparison(comparisonDoc)} />;
}
