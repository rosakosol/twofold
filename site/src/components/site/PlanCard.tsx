import Link from "next/link";
import { Check } from "lucide-react";
import type { ResolvedPlan } from "@/lib/marketing/sanity";
import { PLAN_CTA } from "@/lib/marketing/trialEligibility";

/** "$9.99" and "$5.00": a price for two, and what it comes to each. */
function eachOf(priceLabel: string) {
  const amount = Number(priceLabel.replace(/[^0-9.]/g, ""));
  if (!Number.isFinite(amount) || amount <= 0) return null;
  // In cents, so $19.99 halves to $10.00 rather than the float's $9.99.
  const cents = Math.round(Math.round(amount * 100) / 2);
  return `${priceLabel.replace(/[0-9.,]+/, "")}${(cents / 100).toFixed(2)}`;
}

/**
 * A plan card (docs/TWOFOLD_WEBSITE.md, section 6), the same on the home page's pricing summary and
 * the pricing page. Name, tagline, price and feature list come from the plan documents in Sanity
 * (getResolvedPlans), which the app's paywall copy follows too; the layout and the card's own
 * lines are the spec's. The featured plan, Premium, is emphasised and carries the badge.
 *
 * The pricing page passes the period and the live figures from the offering, and its own checkout
 * button as `action`; the home page uses the monthly defaults and links to /pricing, with
 * `ctaLabel` saying whether that link is a trial (see trialEligibility.ts).
 */
export function PlanCard({
  plan,
  action,
  period = "monthly",
  monthlyFigure = period === "monthly" ? plan.monthly.priceLabel : plan.yearly.perMonthLabel,
  yearlyTotal = plan.yearly.priceLabel,
  saving = null,
  ctaLabel = PLAN_CTA.trial,
}: {
  plan: ResolvedPlan;
  action?: React.ReactNode;
  period?: "monthly" | "yearly";
  /** What it costs a month for the two of you: the monthly price, or the yearly price by month. */
  monthlyFigure?: string;
  yearlyTotal?: string;
  /** The yearly saving in percent, shown on the card in yearly mode. */
  saving?: number | null;
  /** The default link's label. Ignored when `action` is given. */
  ctaLabel?: string;
}) {
  const each = eachOf(monthlyFigure);
  return (
    <article className={`plan-card${plan.featured ? " is-featured" : ""}`} aria-labelledby={`plan-${plan.id}-name`} data-plan={plan.id}>
      {plan.featured && <span className="plan-card-badge">Best for frequent flyers</span>}
      {period === "yearly" && saving !== null && <span className="pill pill-success plan-card-save">Save {saving}%</span>}
      <h3 id={`plan-${plan.id}-name`}>{plan.name}</h3>
      <p className="plan-card-tagline">{plan.tagline}</p>
      <p className="plan-card-price">
        <strong>{monthlyFigure}</strong> a month for you both
      </p>
      <p className="plan-card-each">
        {period === "monthly"
          ? `${each ? `That's ${each} each. ` : ""}Billed monthly, cancel any time.`
          : `Billed yearly at ${yearlyTotal}${each ? `, so ${each} each a month` : ""}. Cancel any time.`}
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
