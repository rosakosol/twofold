import Link from "next/link";
import type { ResolvedPlan } from "@/lib/marketing/sanity";
import { Reveal } from "@/components/marketing/Reveal";

// The home page's pricing preview — the counterpart to FeatureTeaserGrid, and the reader
// getResolvedPlans() was already written to serve (see its comment in sanity.ts), so the
// cards here and the ones on /pricing never disagree about names, prices, or features.
//
// Deliberately a server component with no purchase path: PricingClient carries Supabase auth,
// RevenueCat offerings, and the checkout flow, and pulling that onto the home page would ship
// the whole billing stack to every visitor and give two places for a purchase to go wrong.
// The CTA hands off to /pricing?plan=<id> instead, which that page already understands — it
// scrolls the named card into view rather than rendering a different set.
//
// Monthly, matching PricingClient's own default period, so the figure someone clicks here is
// the figure they land on. No saving pill: this is a teaser, and the yearly discount belongs
// next to the toggle that actually switches term, which is on /pricing.
function PlanPreviewCard({ plan }: { plan: ResolvedPlan }) {
  return (
    <div className={`card plan${plan.featured ? " feature" : ""}`} data-plan={plan.id}>
      <h3>{plan.name}</h3>
      <p className="plan-sub">{plan.tagline}</p>
      <div className="price-line">
        <span className="n">{plan.monthly.priceLabel}</span>
        <span className="per">/mo</span>
      </div>
      <p className="price-foot">Billed monthly · cancel anytime</p>
      <ul className="check-list">
        {plan.features.map((feature) => (
          <li key={feature}>
            <svg className="icon">
              <use href="/assets/icons.svg#icon-check" />
            </svg>
            {feature}
          </li>
        ))}
      </ul>
      <Link className={`btn ${plan.featured ? "btn-primary" : "btn-ghost"}`} href={`/pricing?plan=${plan.id}`}>
        {plan.ctaLabel}
      </Link>
    </div>
  );
}

export function PricingTeaser({ plans }: { plans: { plus: ResolvedPlan; premium: ResolvedPlan } }) {
  return (
    <section aria-labelledby="pricing-teaser-heading">
      <div className="wrap">
        <Reveal className="section-head">
          <p className="eyebrow">
            <svg className="icon">
              <use href="/assets/icons.svg#icon-sparkle" />
            </svg>
            Simple pricing
          </p>
          <h2 id="pricing-teaser-heading">One subscription, both of you</h2>
          <p>Either partner subscribing unlocks everything for the pair of you - there&apos;s no second bill.</p>
        </Reveal>
        <div className="pricing-grid">
          <PlanPreviewCard plan={plans.plus} />
          <PlanPreviewCard plan={plans.premium} />
        </div>
        <p style={{ textAlign: "center", marginTop: 36 }}>
          <Link className="text-link" href="/pricing">
            Compare plans in full
            <svg className="icon">
              <use href="/assets/icons.svg#icon-arrow-right" />
            </svg>
          </Link>
        </p>
      </div>
    </section>
  );
}
