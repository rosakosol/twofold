"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import type { Session } from "@supabase/supabase-js";
import { PLANS, APP_STORE_URL, type Plan } from "@/lib/marketing/config";
import { getSession, onAuthChange, signInWithApple, signOut } from "@/lib/marketing/auth";
import { fetchOfferings, fetchCustomerInfo, findPackage, purchasePackage, activeEntitlements } from "@/lib/marketing/billing";
import { AppStoreQr } from "@/components/marketing/AppStoreQr";

const PENDING_KEY = "twofold_pending_plan";
type PlanId = "plus" | "premium";
type Period = "monthly" | "yearly";

interface Pending {
  planId: PlanId;
  period: Period;
}

function AppStoreBadge({ label = "Download on the" }: { label?: string }) {
  return (
    <a className="appstore-badge" data-appstore-link href={APP_STORE_URL} style={{ margin: "0 auto" }}>
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

function PriceCard({
  plan,
  period,
  featured,
  featureSlice,
  buyingKey,
  onBuy,
}: {
  plan: Plan;
  period: Period;
  featured: boolean;
  featureSlice: string[];
  buyingKey: string | null;
  onBuy: (planId: PlanId, period: Period) => void;
}) {
  const key = `${plan.id}-${period}`;
  const isBuying = buyingKey === key;
  const periodData = plan[period];

  return (
    <div className={`price-card${featured ? " is-featured" : ""}`}>
      {featured && <span className="price-ribbon">Save 50%</span>}
      <h3>{plan.name}</h3>
      <p className="price-tagline">{period === "monthly" ? "Billed monthly · cancel anytime" : "Billed yearly"}</p>
      <div className="price-amount">
        <span className="num">{period === "monthly" ? periodData.priceLabel : periodData.perMonthLabel}</span>
        <span className="period">/mo</span>
      </div>
      <p className="price-sub">{period === "yearly" ? `Works out to ${periodData.priceLabel}/yr` : " "}</p>
      <ul className="feature-list">
        {featureSlice.map((feature) => (
          <li key={feature}>
            <svg className="icon">
              <use href="/assets/icons.svg#icon-check" />
            </svg>
            {feature}
          </li>
        ))}
      </ul>
      <button
        type="button"
        className={`btn ${featured ? "btn-primary" : "btn-outline"} btn-block`}
        disabled={isBuying}
        onClick={() => onBuy(plan.id, period)}
      >
        {isBuying ? "Opening checkout…" : `Get ${plan.id === "plus" ? "Plus" : "Premium"} — ${period === "monthly" ? "Monthly" : "Yearly"}`}
      </button>
    </div>
  );
}

function PricingContent() {
  const searchParams = useSearchParams();
  const requestedPlan = searchParams.get("plan");

  const [tab, setTab] = useState<PlanId>(requestedPlan === "premium" ? "premium" : "plus");
  const [session, setSession] = useState<Session | null>(null);
  const [authLoading, setAuthLoading] = useState(true);
  const [subscribedTier, setSubscribedTier] = useState<"Plus" | "Premium" | null>(null);
  const [showFallback, setShowFallback] = useState(false);
  const [purchaseError, setPurchaseError] = useState<string | null>(null);
  const [purchaseSuccess, setPurchaseSuccess] = useState(false);
  const [buyingKey, setBuyingKey] = useState<string | null>(null);
  const successRef = useRef<HTMLDivElement>(null);
  const attemptedPendingResume = useRef(false);

  async function attemptPurchase(planId: PlanId, period: Period) {
    setPurchaseError(null);
    setShowFallback(false);

    const currentSession = await getSession();
    if (!currentSession) {
      sessionStorage.setItem(PENDING_KEY, JSON.stringify({ planId, period } satisfies Pending));
      await signInWithApple();
      return;
    }

    const plan = PLANS[planId];
    const buyKey = `${planId}-${period}`;
    setBuyingKey(buyKey);

    try {
      const offering = await fetchOfferings(currentSession.user.id);
      const pkg = offering ? findPackage(offering, plan[period].packageId) : null;

      if (!pkg) {
        // Web Billing not wired up yet (placeholder key / offering not published). Don't
        // dead-end the funnel — steer to the App Store instead of failing silently.
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
          ? "Web checkout isn't live yet — download the app to subscribe on iOS for now."
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
            const { planId, period } = JSON.parse(pending) as Pending;
            setTab(planId);
            attemptPurchase(planId, period);
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

  async function handleSignOut() {
    await signOut();
    window.location.reload();
  }

  const plusFeatures = PLANS.plus.features.slice(0, 4);
  const premiumFeatures = PLANS.premium.features.slice(0, 5);

  return (
    <>
      <section className="page-hero" style={{ paddingBottom: 0 }}>
        <p className="eyebrow">
          <svg className="icon">
            <use href="/assets/icons.svg#icon-sparkle" />
          </svg>
          Pricing
        </p>
        <h1>One subscription, shared by both of you</h1>
        <p>Subscribe here on the web or right inside the app — either partner&apos;s subscription unlocks the full experience for you both.</p>
      </section>

      <section style={{ paddingTop: 32 }}>
        <div className="wrap-narrow" style={{ textAlign: "center", marginBottom: 28 }}>
          {!authLoading &&
            (session ? (
              <>
                <span className="auth-status">
                  <svg className="icon">
                    <use href="/assets/icons.svg#icon-check-circle" />
                  </svg>{" "}
                  Signed in as {session.user.email || "your Apple ID"}
                </span>
                <button
                  type="button"
                  className="text-link"
                  style={{ marginLeft: 12, background: "none", border: "none", cursor: "pointer" }}
                  onClick={handleSignOut}
                >
                  Sign out
                </button>
              </>
            ) : (
              <span className="form-status" data-state="info">
                You&apos;ll sign in with Apple at checkout — it&apos;s how we match your web purchase to your Twofold account.
              </span>
            ))}
        </div>

        <div style={{ display: "flex", justifyContent: "center" }}>
          <div className="pricing-toggle">
            <button type="button" className={tab === "plus" ? "is-active" : undefined} onClick={() => setTab("plus")}>
              Plus
            </button>
            <button type="button" className={tab === "premium" ? "is-active" : undefined} onClick={() => setTab("premium")}>
              Premium
            </button>
          </div>
        </div>

        <div className="wrap">
          {subscribedTier ? (
            <div className="waitlist-card" style={{ marginTop: 28, maxWidth: 520 }}>
              <div
                className="icon-wrap"
                style={{
                  width: 44,
                  height: 44,
                  borderRadius: "50%",
                  background: "var(--card-bg-alt)",
                  color: "var(--leaf-green-deep)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  margin: "0 auto 14px",
                }}
              >
                <svg className="icon" style={{ width: 22, height: 22 }}>
                  <use href="/assets/icons.svg#icon-check-circle" />
                </svg>
              </div>
              <h3 style={{ marginBottom: 16 }}>
                You already have Twofold {subscribedTier} — open the app and sign in with the same Apple ID to use it.
              </h3>
              <AppStoreBadge label="Open on the" />
            </div>
          ) : purchaseSuccess ? (
            <div ref={successRef} className="waitlist-card" style={{ marginTop: 28, maxWidth: 560 }}>
              <div
                className="icon-wrap"
                style={{
                  width: 52,
                  height: 52,
                  borderRadius: "50%",
                  background: "rgba(111,191,139,0.15)",
                  color: "var(--leaf-green-deep)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  margin: "0 auto 16px",
                }}
              >
                <svg className="icon" style={{ width: 26, height: 26 }}>
                  <use href="/assets/icons.svg#icon-check-circle" />
                </svg>
              </div>
              <h2 style={{ marginBottom: 10 }}>You&apos;re all set 🎉</h2>
              <p style={{ marginBottom: 24 }}>
                Download Twofold and sign in with the <strong>same Apple ID</strong> you just used — your subscription will
                already be active.
              </p>
              <AppStoreBadge />
            </div>
          ) : (
            <>
              <div className="pricing-grid">
                {tab === "plus" ? (
                  <>
                    <PriceCard plan={PLANS.plus} period="monthly" featured={false} featureSlice={plusFeatures} buyingKey={buyingKey} onBuy={attemptPurchase} />
                    <PriceCard plan={PLANS.plus} period="yearly" featured featureSlice={plusFeatures} buyingKey={buyingKey} onBuy={attemptPurchase} />
                  </>
                ) : (
                  <>
                    <PriceCard plan={PLANS.premium} period="monthly" featured={false} featureSlice={premiumFeatures} buyingKey={buyingKey} onBuy={attemptPurchase} />
                    <PriceCard plan={PLANS.premium} period="yearly" featured featureSlice={premiumFeatures} buyingKey={buyingKey} onBuy={attemptPurchase} />
                  </>
                )}
              </div>

              {purchaseError && (
                <p className="form-status" data-state="error" style={{ textAlign: "center", marginTop: 20 }}>
                  {purchaseError}
                </p>
              )}

              {showFallback && (
                <div className="waitlist-card" style={{ marginTop: 28, maxWidth: 520 }}>
                  <h3 style={{ marginBottom: 8 }}>Web checkout is being finalized</h3>
                  <p style={{ marginBottom: 20 }}>You can subscribe right now from the iOS app instead — it&apos;ll be ready here shortly.</p>
                  <AppStoreBadge />
                </div>
              )}
            </>
          )}

          <div className="trust-strip reveal" style={{ marginTop: 40 }}>
            <span className="trust-item">
              <svg className="icon">
                <use href="/assets/icons.svg#icon-lock" />
              </svg>
              Secure checkout via Stripe
            </span>
            <span className="trust-item">
              <svg className="icon">
                <use href="/assets/icons.svg#icon-shield" />
              </svg>
              Cancel anytime
            </span>
            <span className="trust-item">
              <svg className="icon">
                <use href="/assets/icons.svg#icon-users" />
              </svg>
              One subscription, two people
            </span>
          </div>

          <div className="qr-card only-desktop reveal">
            <AppStoreQr />
            <div className="qr-card-copy">
              <strong>Prefer to subscribe in the app?</strong>
              <span>Scan to download Twofold on iOS and subscribe from the paywall instead.</span>
            </div>
          </div>
        </div>
      </section>

      <section aria-labelledby="compare-heading">
        <div className="wrap-narrow">
          <div className="section-head reveal">
            <p className="eyebrow">
              <svg className="icon">
                <use href="/assets/icons.svg#icon-sparkle" />
              </svg>
              Compare plans
            </p>
            <h2 id="compare-heading">Plus vs. Premium</h2>
          </div>
          <div className="compare-table-wrap reveal">
            <table className="compare-table">
              <thead>
                <tr>
                  <th></th>
                  <th>Plus</th>
                  <th>Premium</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>Trips &amp; memories</td>
                  <td>Unlimited</td>
                  <td>Unlimited</td>
                </tr>
                <tr>
                  <td>Live flight tracking</td>
                  <td>Up to 5/month</td>
                  <td>Up to 20/month</td>
                </tr>
                <tr>
                  <td>Questions &amp; games</td>
                  <td>500+</td>
                  <td>2000+</td>
                </tr>
                <tr>
                  <td>Relationship Globe</td>
                  <td>Standard</td>
                  <td>Interactive 3D</td>
                </tr>
                <tr>
                  <td>Home &amp; Lock Screen widgets</td>
                  <td>Standard widgets</td>
                  <td>+ Premium widget styles</td>
                </tr>
                <tr>
                  <td>Relationship Record PDF export</td>
                  <td>
                    <svg className="icon icon-dash">
                      <use href="/assets/icons.svg#icon-x" />
                    </svg>
                  </td>
                  <td>
                    <svg className="icon icon-check">
                      <use href="/assets/icons.svg#icon-check" />
                    </svg>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <section aria-labelledby="pricing-faq-heading">
        <div className="wrap-narrow">
          <div className="section-head reveal">
            <p className="eyebrow">
              <svg className="icon">
                <use href="/assets/icons.svg#icon-sparkle" />
              </svg>
              Billing
            </p>
            <h2 id="pricing-faq-heading">A few things worth knowing</h2>
          </div>
          <div className="faq-list reveal">
            <details className="faq-item">
              <summary>
                Does subscribing here work the same as in the app?
                <svg className="icon icon-chevron">
                  <use href="/assets/icons.svg#icon-chevron-down" />
                </svg>
              </summary>
              <div className="faq-body">
                Yes — subscribing on the web unlocks Twofold Plus or Premium on your account the same way an in-app purchase
                does. Sign in with the same Apple ID in the app and it&apos;ll already be active.
              </div>
            </details>
            <details className="faq-item">
              <summary>
                Can I cancel anytime?
                <svg className="icon icon-chevron">
                  <use href="/assets/icons.svg#icon-chevron-down" />
                </svg>
              </summary>
              <div className="faq-body">
                Yes. Web subscriptions can be managed or cancelled from your account, and App Store subscriptions from your
                device&apos;s Settings — either way, you keep access until the end of the period you&apos;ve already paid for.
              </div>
            </details>
            <details className="faq-item">
              <summary>
                Does a subscription cover both partners?
                <svg className="icon icon-chevron">
                  <use href="/assets/icons.svg#icon-chevron-down" />
                </svg>
              </summary>
              <div className="faq-body">
                Yes — once you&apos;re connected in the app, either partner&apos;s active Plus or Premium subscription unlocks
                the full experience for both of you.
              </div>
            </details>
          </div>
          <p style={{ textAlign: "center", marginTop: 24 }}>
            <a className="text-link" href="/faq">
              More questions
              <svg className="icon">
                <use href="/assets/icons.svg#icon-arrow-right" />
              </svg>
            </a>
          </p>
        </div>
      </section>
    </>
  );
}

export function PricingClient() {
  return (
    <Suspense>
      <PricingContent />
    </Suspense>
  );
}
