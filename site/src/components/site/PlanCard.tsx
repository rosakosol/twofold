import Link from "next/link";
import { Check } from "lucide-react";
import type { ResolvedPlan } from "@/lib/marketing/sanity";

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
 * `action` replaces the default link to /pricing?plan=, for the pricing page's own checkout.
 */
export function PlanCard({ plan, action }: { plan: ResolvedPlan; action?: React.ReactNode }) {
  const each = eachOf(plan.monthly.priceLabel);
  return (
    <article className={`plan-card${plan.featured ? " is-featured" : ""}`} aria-labelledby={`plan-${plan.id}-name`} data-plan={plan.id}>
      {plan.featured && <span className="plan-card-badge">Best for frequent flyers</span>}
      <h3 id={`plan-${plan.id}-name`}>{plan.name}</h3>
      <p className="plan-card-tagline">{plan.tagline}</p>
      <p className="plan-card-price">
        <strong>{plan.monthly.priceLabel}</strong> a month for you both
      </p>
      <p className="plan-card-each">
        {each ? `That's ${each} each. ` : ""}Billed monthly, cancel any time.
      </p>
      {action ?? (
        <Link className={`btn ${plan.featured ? "btn-primary" : "btn-secondary"}`} href={`/pricing?plan=${plan.id}`}>
          Start 14-day free trial
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
