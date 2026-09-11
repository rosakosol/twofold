"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import type { Session } from "@supabase/supabase-js";
import { PLANS } from "@/lib/marketing/config";
import type { ResolvedPlan } from "@/lib/marketing/sanity";
import { getSession, onAuthChange, signInWithApple, signOut } from "@/lib/marketing/auth";
import { providerFallbackName, providerLabel, sessionProvider } from "@/lib/marketing/provider";
import {
  fetchOfferings,
  fetchCustomerInfo,
  findPackage,
  purchasePackage,
  activeEntitlements,
  fetchLivePrices,
  anonymousAppUserId,
  type LivePrices,
} from "@/lib/marketing/billing";
import { priceLabelFor, perMonthLabelFor, yearlySavingPercent, savingPercent } from "@/lib/marketing/priceDisplay";
import { Reveal } from "@/components/marketing/Reveal";
import { PlanComparison } from "@/components/marketing/PlanComparison";
import type { ResolvedPlanComparison } from "@/lib/marketing/planComparisonFallback";

const PENDING_KEY = "twofold_pending_plan";
type PlanId = "plus" | "premium";
type Period = "monthly" | "yearly";

interface Pending {
  planId: PlanId;
  period: Period;
}

function AppStoreBadge({ label = "Download on the" }: { label?: string }) {
  return (
    <a className="appstore-badge" data-appstore-link href="https://apps.apple.com/app/id0000000000" style={{ margin: "0 auto" }}>
      <svg className="icon">
        <use href="/assets/icons.svg#icon-apple" />
      </svg>
      <span className="badge-text">
        <small>{label}</small>
        <strong>App&nbsp;Store</strong>
      </span>
    </a>
  );
}

function PlanCard({
  plan,
  period,
  buyingKey,
  onBuy,
  livePrices,
}: {
  plan: ResolvedPlan;
  period: Period;
  buyingKey: string | null;
  onBuy: (planId: PlanId, period: Period) => void;
  livePrices: LivePrices;
}) {
  const key = `${plan.id}-${period}`;
  const isBuying = buyingKey === key;

  // ResolvedPlan carries the editable labels; the package identifiers that key the live
  // offering only exist in code, so they come from PLANS - same lookup attemptPurchase does.
  const packages = PLANS[plan.id];

  // Live where the offering has it, the plan's own label otherwise. The label renders first
  // and is replaced in place once the offering resolves, so there is never an empty price -
  // only one that may refine itself into the buyer's own currency.
  const monthlyFigure =
    period === "monthly"
      ? priceLabelFor(livePrices, packages.monthly.packageId, plan.monthly.priceLabel)
      : perMonthLabelFor(livePrices, packages.yearly.packageId, plan.yearly.perMonthLabel);
  const yearlyTotal = priceLabelFor(livePrices, packages.yearly.packageId, plan.yearly.priceLabel);

  return (
    <div className={`card plan${plan.featured ? " feature" : ""}`}>
      <h3>{plan.name}</h3>
      <p className="plan-sub">{plan.tagline}</p>
      <div className="price-line">
        <span className="n">{monthlyFigure}</span>
        <span className="per">/mo</span>
      </div>
      <p className="price-foot">
        {period === "yearly" ? `Billed yearly - works out to ${yearlyTotal}/yr` : "Billed monthly · cancel anytime"}
      </p>
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
      <button type="button" className={`btn ${plan.featured ? "btn-primary" : "btn-ghost"}`} disabled={isBuying} onClick={() => onBuy(plan.id, period)}>
        {isBuying ? "Opening checkout…" : plan.ctaLabel}
      </button>
    </div>
  );
}

function PricingContent({
  plans,
  comparison,
}: {
  plans: { plus: ResolvedPlan; premium: ResolvedPlan };
  comparison: ResolvedPlanComparison;
}) {
  const searchParams = useSearchParams();
  const requestedPlan = searchParams.get("plan");

  const [period, setPeriod] = useState<Period>("yearly");
  const [session, setSession] = useState<Session | null>(null);
  const [authLoading, setAuthLoading] = useState(true);
  const [subscribedTier, setSubscribedTier] = useState<"Plus" | "Premium" | null>(null);
  const [showFallback, setShowFallback] = useState(false);
  const [purchaseError, setPurchaseError] = useState<string | null>(null);
  const [purchaseSuccess, setPurchaseSuccess] = useState(false);
  const [buyingKey, setBuyingKey] = useState<string | null>(null);
  // Empty until the offering resolves; every read falls back to the plan's own label, so
  // the cards are fully priced on first paint and only refine afterwards.
  const [livePrices, setLivePrices] = useState<LivePrices>({});
  const successRef = useRef<HTMLDivElement>(null);
  // Whatever this session was actually created with - Apple here, but equally a Google or
  // magic-link session carried over from the feedback board, which shares this project.
  const provider = sessionProvider(session);
  const attemptedPendingResume = useRef(false);

  // "Save 50%" was typed into the markup, so a price change in Stripe would have left it
  // advertising a discount that no longer existed. Derived from the live offering, falling
  // back to PLANS' own numbers - both plans are priced at the same ratio, so Plus speaks for
  // the toggle. Null hides the pill rather than showing "Save 0%".
  const yearlySaving =
    yearlySavingPercent(
      livePrices[PLANS.plus.monthly.packageId],
      livePrices[PLANS.plus.yearly.packageId]
    ) ?? savingPercent(PLANS.plus.monthly.price, PLANS.plus.yearly.price);

  async function attemptPurchase(planId: PlanId, billingPeriod: Period) {
    setPurchaseError(null);
    setShowFallback(false);

    const currentSession = await getSession();
    if (!currentSession) {
      sessionStorage.setItem(PENDING_KEY, JSON.stringify({ planId, period: billingPeriod } satisfies Pending));
      await signInWithApple();
      return;
    }

    const plan = PLANS[planId];
    const buyKey = `${planId}-${billingPeriod}`;
    setBuyingKey(buyKey);

    try {
      const offering = await fetchOfferings(currentSession.user.id);
      const pkg = offering ? findPackage(offering, plan[billingPeriod].packageId) : null;

      if (!pkg) {
        // Web Billing not wired up yet (placeholder key / offering not published). Don't
        // dead-end the funnel - steer to the App Store instead of failing silently.
        setBuyingKey(null);
        setShowFallback(true);
        return;
      }

      const { customerInfo } = await purchasePackage(currentSession.user.id, pkg);
      const active = activeEntitlements(customerInfo);
      if (active.length) {
        setPurchaseSuccess(true);
        requestAnimationFrame(() => successRef.current?.scrollIntoView({ behavior: "smooth", block: "start" }));
      } else {
        setBuyingKey(null);
      }
    } catch (err) {
      setBuyingKey(null);
      const message = err instanceof Error ? err.message : "";
      setPurchaseError(
        message.includes("available")
          ? "Web checkout isn't live yet - download the app to subscribe on iOS for now."
          : "Something went wrong with checkout. Please try again."
      );
    }
  }

  async function checkSubscriptionStatus(currentSession: Session) {
    const customerInfo = await fetchCustomerInfo(currentSession.user.id);
    const active = activeEntitlements(customerInfo);
    if (active.includes(PLANS.premium.entitlement)) {
      setSubscribedTier("Premium");
    } else if (active.includes(PLANS.plus.entitlement)) {
      setSubscribedTier("Plus");
    } else {
      setSubscribedTier(null);
    }
    return active;
  }

  useEffect(() => {
    let cancelled = false;

    (async () => {
      const initialSession = await getSession();
      if (cancelled) return;
      setSession(initialSession);
      setAuthLoading(false);

      if (initialSession) {
        const active = await checkSubscriptionStatus(initialSession);
        if (cancelled) return;

        // Resume a purchase that was interrupted by the Apple sign-in redirect.
        if (!attemptedPendingResume.current) {
          attemptedPendingResume.current = true;
          const pending = sessionStorage.getItem(PENDING_KEY);
          if (pending && active.length === 0) {
            sessionStorage.removeItem(PENDING_KEY);
            const { planId, period: pendingPeriod } = JSON.parse(pending) as Pending;
            setPeriod(pendingPeriod);
            attemptPurchase(planId, pendingPeriod);
          }
        }
      }
    })();

    const unsubscribe = onAuthChange((newSession) => {
      setSession(newSession);
      if (newSession) checkSubscriptionStatus(newSession);
    });

    return () => {
      cancelled = true;
      unsubscribe();
    };
  }, []);

  // Separate from the auth effect on purpose: prices have to be on screen for someone who
  // has not signed in and may never sign in, so this cannot wait on a session. Re-runs once a
  // session appears so the offering is read under the real app user id, which is what any
  // per-customer pricing would key off.
  useEffect(() => {
    let cancelled = false;

    (async () => {
      const appUserId = session?.user.id ?? (await anonymousAppUserId());
      if (!appUserId || cancelled) return;
      const prices = await fetchLivePrices(appUserId);
      if (!cancelled && Object.keys(prices).length) setLivePrices(prices);
    })();

    return () => {
      cancelled = true;
    };
  }, [session]);

  useEffect(() => {
    if (requestedPlan === "premium" || requestedPlan === "plus") {
      // The referring page (e.g. the Home pricing preview) named a specific plan -
      // scroll it into view rather than changing which cards render, since both
      // plans always render together now.
      document.getElementById(`plan-${requestedPlan}`)?.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  }, [requestedPlan]);

  async function handleSignOut() {
    await signOut();
    window.location.reload();
  }

  return (
    <>
      <header className="page-head">
        <Reveal className="wrap">
          <span className="eyebrow">
            <svg className="icon">
              <use href="/assets/icons.svg#icon-sparkle" />
            </svg>
            Pricing
          </span>
          <h1>One subscription, shared by both of you</h1>
          <p className="lead">Subscribe here on the web or right inside the app - either partner&apos;s subscription unlocks the full experience for you both.</p>
          {/* Signed-out only. It describes something about to happen ("you'll sign in at
              checkout"), so it's simply untrue once there's a session - and it names Apple,
              which attemptPurchase does force for a signed-out buyer but which says nothing
              about a Google or magic-link session carried over from the feedback board. The
              "Signed in as …" line below replaces it, and says which account. Gated on
              !authLoading as well so a signed-in visitor never sees it flash on first paint. */}
          {!authLoading && !session && (
            <div className="apple-note">
              <svg className="icon">
                <use href="/assets/icons.svg#icon-apple" />
              </svg>
              You&apos;ll sign in with Apple at checkout - it&apos;s how we match your web purchase to your
              Twofold account.
            </div>
          )}
        </Reveal>
      </header>

      <section style={{ paddingTop: 30 }}>
        <div className="wrap" style={{ textAlign: "center" }}>
          {!authLoading && session && (
            <div style={{ marginBottom: 20 }}>
              <span className="auth-status">
                <svg className="icon">
                  <use href="/assets/icons.svg#icon-check-circle" />
                </svg>
                Signed in as {session.user.email || providerFallbackName(provider)}
              </span>
              <button
                type="button"
                className="text-link"
                style={{ marginLeft: 12, background: "none", border: "none", cursor: "pointer" }}
                onClick={handleSignOut}
              >
                Sign out
              </button>
            </div>
          )}

          {subscribedTier ? (
            <div className="card waitlist-card" style={{ marginTop: 12, maxWidth: 520, marginLeft: "auto", marginRight: "auto" }}>
              <h3 style={{ marginBottom: 16 }}>
                You already have Twofold {subscribedTier} - open the app and sign in with the same{" "}
                {providerLabel(provider)} to use it.
              </h3>
              <AppStoreBadge label="Open on the" />
            </div>
          ) : purchaseSuccess ? (
            <div ref={successRef} className="card waitlist-card" style={{ marginTop: 12, maxWidth: 560, marginLeft: "auto", marginRight: "auto" }}>
              <h2 style={{ marginBottom: 10 }}>You&apos;re all set 🎉</h2>
              <p style={{ marginBottom: 24 }}>
                Download Twofold and sign in with the <strong>same {providerLabel(provider)}</strong> you just
                used - your subscription will already be active.
              </p>
              <AppStoreBadge />
            </div>
          ) : (
            <>
              <Reveal className="billing-toggle" role="group">
                <button type="button" className={period === "monthly" ? "active" : undefined} onClick={() => setPeriod("monthly")}>
                  Monthly
                </button>
                <button type="button" className={period === "yearly" ? "active" : undefined} onClick={() => setPeriod("yearly")}>
                  Yearly
                  {yearlySaving !== null && <span className="save-pill">Save {yearlySaving}%</span>}
                </button>
              </Reveal>

              <div className="pricing-grid">
                <div id="plan-plus">
                  <PlanCard plan={plans.plus} period={period} buyingKey={buyingKey} onBuy={attemptPurchase} livePrices={livePrices} />
                </div>
                <div id="plan-premium">
                  <PlanCard plan={plans.premium} period={period} buyingKey={buyingKey} onBuy={attemptPurchase} livePrices={livePrices} />
                </div>
              </div>

              {purchaseError && (
                <p className="form-status" data-state="error" style={{ textAlign: "center", marginTop: 20 }}>
                  {purchaseError}
                </p>
              )}

              {showFallback && (
                <div className="card waitlist-card" style={{ marginTop: 28, maxWidth: 520, marginLeft: "auto", marginRight: "auto" }}>
                  <h3 style={{ marginBottom: 8 }}>Web checkout is being finalized</h3>
                  <p style={{ marginBottom: 20 }}>You can subscribe right now from the iOS app instead - it&apos;ll be ready here shortly.</p>
                  <AppStoreBadge />
                </div>
              )}

              <PlanComparison comparison={comparison} />
            </>
          )}

          {/* Below the comparison table, not the cards: someone still weighing the two plans
              scrolls the table first, and the FAQ is the next thing they want if it didn't
              settle it. Outside the purchase-state branch above so it survives checkout too. */}
          <Reveal className="pricing-foot">
            <a className="arrow-link" href="/faq">
              More questions
              <svg className="icon">
                <use href="/assets/icons.svg#icon-arrow-right" />
              </svg>
            </a>
          </Reveal>
        </div>
      </section>
    </>
  );
}

export function PricingClient({
  plans,
  comparison,
}: {
  plans: { plus: ResolvedPlan; premium: ResolvedPlan };
  comparison: ResolvedPlanComparison;
}) {
  return (
    <Suspense>
      <PricingContent plans={plans} comparison={comparison} />
    </Suspense>
  );
}
