import Link from "next/link";
import { Check } from "lucide-react";
import type { ResolvedPlan } from "@/lib/marketing/sanity";
import type { PlanFigures } from "@/lib/marketing/priceDisplay";
import { PLAN_CTA } from "@/lib/marketing/trialEligibility";

/** Stands in for a figure until the prices arrive: about a price's width, so nothing moves. */
function Pending() {
  return <span className="plan-card-pending" aria-hidden />;
}

/**
 * A plan card (docs/TWOFOLD_WEBSITE.md, section 6), the same on the home page's pricing summary and
 * the pricing page. Name, tagline and feature list come from the plan documents in Sanity
 * (getResolvedPlans), which the app's paywall copy follows too, and the prices from RevenueCat; the
 * layout and the card's own lines are the spec's. The featured plan, Premium, is emphasised and
 * carries the badge.
 *
 * Both pages pass the same figures, from the live offering (useLivePrices, figuresForPlan). The
 * pricing page adds the period and its own checkout button as `action`; the home page uses the
 * monthly default and links to /pricing, with `ctaLabel` saying whether that link is a trial (see
 * trialEligibility.ts).
 */
export function PlanCard({
  plan,
  figures,
  action,
  period = "monthly",
  ctaLabel = PLAN_CTA.trial,
}: {
  plan: ResolvedPlan;
  /**
   * Every money figure on the card, formatted for this visitor (see priceDisplay.ts). Null until
   * the live prices have answered or timed out, and the card draws placeholders instead - which is
   * also what the server renders, since it cannot know which currency the visitor will be shown.
   */
  figures: PlanFigures | null;
  action?: React.ReactNode;
  period?: "monthly" | "yearly";
  /** The default link's label. Ignored when `action` is given. */
  ctaLabel?: string;
}) {
  const monthlyFigure = figures && (period === "monthly" ? figures.monthly : figures.yearlyPerMonth);
  const each = figures && (period === "monthly" ? figures.monthlyEach : figures.yearlyPerMonthEach);
  const saving = figures?.saving ?? null;
  const pending = figures ? undefined : true;

  return (
    <article className={`plan-card${plan.featured ? " is-featured" : ""}`} aria-labelledby={`plan-${plan.id}-name`} data-plan={plan.id}>
      {plan.featured && <span className="plan-card-badge">Best for frequent flyers</span>}
      {period === "yearly" && saving !== null && <span className="pill pill-success plan-card-save">Save {saving}%</span>}
      <h3 id={`plan-${plan.id}-name`}>{plan.name}</h3>
      <p className="plan-card-tagline">{plan.tagline}</p>
      <p className="plan-card-price" aria-busy={pending}>
        <strong>{monthlyFigure ?? <Pending />}</strong> a month for you both
      </p>
      <p className="plan-card-each" aria-busy={pending}>
        {period === "monthly" ? (
          <>That&apos;s {each ?? <Pending />} each. Billed monthly, cancel any time.</>
        ) : (
          <>
            Billed yearly at {figures?.yearlyTotal ?? <Pending />}, so {each ?? <Pending />} each a month. Cancel
            any time.
          </>
        )}
      </p>
      {action ?? (
        <Link className={`btn ${plan.featured ? "btn-primary" : "btn-secondary"}`} href={`/pricing?plan=${plan.id}`}>
          {ctaLabel}
        </Link>
      )}
      <ul className="plan-card-features">
        {plan.features.map((feature) => (
          <li key={feature}>
            <Check aria-hidden />
            {feature}
          </li>
        ))}
      </ul>
    </article>
  );
}
