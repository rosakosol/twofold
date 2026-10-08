"use client";

import type { ResolvedPlan } from "@/lib/marketing/sanity";
import { useUser } from "@/lib/auth/useUser";
import { useTrialStanding } from "@/lib/marketing/useTrialStanding";
import { planCtaLabel, standingOffersTrial } from "@/lib/marketing/trialEligibility";
import { PlanCard } from "@/components/site/PlanCard";

/**
 * The home page's pricing summary: the lead line and the two plan cards, whose trial copy depends
 * on who is looking. Signed out it renders exactly what the server did; somebody signed in who has
 * subscribed before is not offered a trial they will not get.
 */
export function HomePlans({ plans }: { plans: { plus: ResolvedPlan; premium: ResolvedPlan } }) {
  const { user, isLoading } = useUser();
  const standing = useTrialStanding(isLoading ? undefined : (user?.id ?? null));
  const ctaLabel = planCtaLabel(standing);

  return (
    <>
      <header className="home-section-head">
        <h2 id="pricing-title">One subscription, both of you</h2>
        <p className="lead">
          {standingOffersTrial(standing) ? "Start with a two-week free trial. " : ""}Billed monthly, cancel any time.
        </p>
      </header>
      <div className="plan-cards">
        <PlanCard plan={plans.plus} ctaLabel={ctaLabel} />
        <PlanCard plan={plans.premium} ctaLabel={ctaLabel} />
      </div>
    </>
  );
}
