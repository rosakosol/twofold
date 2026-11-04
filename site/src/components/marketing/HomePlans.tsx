"use client";

import type { ResolvedPlan } from "@/lib/marketing/sanity";
import { useUser } from "@/lib/auth/useUser";
import { useLivePrices } from "@/lib/marketing/useLivePrices";
import { useTrialStanding } from "@/lib/marketing/useTrialStanding";
import { figuresForPlan } from "@/lib/marketing/priceDisplay";
import { planCtaLabel, standingOffersTrial } from "@/lib/marketing/trialEligibility";
import { PlanCard } from "@/components/site/PlanCard";

/**
 * The home page's pricing summary: the lead line and the two plan cards, whose trial copy depends
 * on who is looking. Signed out it renders exactly what the server did; somebody signed in who has
 * subscribed before is not offered a trial they will not get.
 *
 * Priced the way /pricing is, from the same live offering (useLivePrices), so the figure somebody
 * clicks here is the figure they land on, in their own currency. These cards used to print the AUD
 * labels from Studio to everybody, so a visitor in London read "$9.99" here and "£7.99" one click
 * later.
 */
export function HomePlans({ plans }: { plans: { plus: ResolvedPlan; premium: ResolvedPlan } }) {
  const { user, isLoading } = useUser();
  const userId = isLoading ? undefined : (user?.id ?? null);
  const standing = useTrialStanding(userId);
  const ctaLabel = planCtaLabel(standing);
  const { prices, status } = useLivePrices(userId);

  return (
    <>
      <header className="home-section-head">
        <h2 id="pricing-title">One subscription, both of you</h2>
        <p className="lead">
          {standingOffersTrial(standing) ? "Start with a two-week free trial. " : ""}Billed monthly, cancel any time.
        </p>
      </header>
      <div className="plan-cards">
        <PlanCard plan={plans.plus} figures={status === "loading" ? null : figuresForPlan(prices, "plus")} ctaLabel={ctaLabel} />
        <PlanCard plan={plans.premium} figures={status === "loading" ? null : figuresForPlan(prices, "premium")} ctaLabel={ctaLabel} />
      </div>
    </>
  );
}
