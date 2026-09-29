"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import type { Session } from "@supabase/supabase-js";
import { APP_STORE_URL, PLANS } from "@/lib/marketing/config";
import type { ResolvedPlan } from "@/lib/marketing/sanity";
import {
  getSession,
  onAuthChange,
  signInWithProvider,
  signUpWithPassword,
  signInWithPassword,
  isExistingAccountError,
  signOut,
} from "@/lib/marketing/auth";
import { isStrongEnough, passwordStrengthLabel } from "@/lib/marketing/passwordStrength";
import { providerFallbackName, providerLabel, sessionProvider } from "@/lib/marketing/provider";
import { createClient } from "@/lib/supabase/client";
import {
  fetchOfferings,
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

  // Per-plan rather than the single figure on the period toggle: the two tiers could be
  // discounted differently, and a card claiming a saving it doesn't give is worse than no
  // claim at all. Live prices where available, PLANS' own numbers otherwise.
  const saving =
    yearlySavingPercent(livePrices[packages.monthly.packageId], livePrices[packages.yearly.packageId]) ??
    savingPercent(packages.monthly.price, packages.yearly.price);

  return (
    <div className={`card plan${plan.featured ? " feature" : ""}`} data-plan={plan.id}>
      {period === "yearly" && saving !== null && <span className="plan-save">Save {saving}% vs monthly</span>}
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

  // Monthly by default: it is the smaller commitment and the honest headline figure, and
  // the yearly saving is right there on the toggle for anyone it appeals to. The home page
  // preview shows monthly for the same reason, so the price clicked is the price landed on.
  const [period, setPeriod] = useState<Period>("monthly");
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
  // Set when a signed-out visitor picks a plan: which plan they picked, and therefore that the
  // sign-in step is what is on screen. Null the rest of the time.
  const [signInFor, setSignInFor] = useState<Pending | null>(null);
  const [oauthPending, setOauthPending] = useState<"apple" | "google" | null>(null);
  // Create by default: most people who reach this step have no Twofold account, because anyone who
  // installed the app first met a non-dismissable paywall during onboarding and subscribed there.
  const [authMode, setAuthMode] = useState<"create" | "signin">("create");
  const [firstName, setFirstName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [acceptedTerms, setAcceptedTerms] = useState(false);
  const [emailSubmitting, setEmailSubmitting] = useState(false);
  const [signInError, setSignInError] = useState<string | null>(null);
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
      // Ask which account, rather than answering for them.
      //
      // This called `signInWithApple()` outright, sending every buyer into an Apple redirect — while
      // the app signs people in with Apple, Google *or* an email address (BackendService.swift). A
      // Google or email account holder got an Apple identity instead, which is a different Supabase
      // user, and the subscription attached to that one: paid for, and invisible in the app they
      // bought it for. Apple's Hide My Email makes it certain rather than likely, since a relay
      // address cannot match the account they already have.
      //
      // Nothing about the payment needed Apple. Web checkout bills a card through Stripe (see
      // billing.ts) — the sign-in is only how the entitlement finds an account, so the right set of
      // methods is whichever ones can reach the account they already use.
      sessionStorage.setItem(PENDING_KEY, JSON.stringify({ planId, period: billingPeriod } satisfies Pending));
      setSignInFor({ planId, period: billingPeriod });
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

  /**
   * Whether this person already has a subscription — read from their profile row rather than from
   * RevenueCat's client SDK.
   *
   * The SDK can only answer for the customer it is configured as, and that was never the whole
   * picture. It could not see an App Store subscription at all, so an iOS subscriber opening this
   * page was told they had nothing and invited to buy a second one. Now that `billing.ts`
   * canonicalises the app user id to the uppercase spelling the app uses, it would also stop seeing
   * the web customers created under the old lowercase spelling — the same harm, aimed at the people
   * this fix is for.
   *
   * `profiles` has neither blind spot. `revenuecat-webhook` writes it from whichever spelling an
   * event arrives under, and `reconcile-subscriptions` sweeps up behind it, so one row is right
   * about both channels and both spellings.
   *
   * Three outcomes, not two. A failed read is `null` — unknown — never `false`: the caller uses this
   * to decide whether to resume a purchase, and guessing "no subscription" from a network blip is
   * how somebody gets charged twice.
   */
  async function startOAuth(provider: "apple" | "google") {
    setSignInError(null);
    setOauthPending(provider);
    try {
      await signInWithProvider(provider);
      // On success the browser leaves for the provider, so there is no success state to set.
    } catch {
      setOauthPending(null);
      setSignInError("We couldn't start that sign-in. Please try again.");
    }
  }

  /// Mirrors `CreateAccountView.canContinue` and `SaveAccountView.canContinueWithEmail` field for
  /// field — see lib/marketing/passwordStrength.ts for the strength half. An account the app would
  /// refuse to create must not be creatable here, or the two surfaces disagree about who has a
  /// valid account.
  const canSubmitEmail =
    authMode === "signin"
      ? email.trim() !== "" && password !== ""
      : firstName.trim() !== "" &&
        email.trim() !== "" &&
        password.length >= 6 &&
        confirmPassword === password &&
        isStrongEnough(password) &&
        acceptedTerms;

  async function submitEmailAuth(event: React.FormEvent) {
    event.preventDefault();
    if (!canSubmitEmail || emailSubmitting) return;
    setSignInError(null);
    setEmailSubmitting(true);

    try {
      if (authMode === "signin") {
        await signInWithPassword(email, password);
      } else {
        const data = await signUpWithPassword(firstName, email, password);
        // Supabase can report an existing address as a success carrying a user with no identities,
        // rather than as an error — see isExistingAccountError. Treated the same either way: send
        // them to sign in rather than leaving them on a form that appeared to work.
        if (isExistingAccountError(null, data)) {
          setAuthMode("signin");
          setSignInError("An account with this email already exists. Sign in to use it.");
          setEmailSubmitting(false);
          return;
        }
      }
      // The session lands via onAuthChange, and the pending-plan effect resumes the purchase.
    } catch (err) {
      if (authMode === "create" && isExistingAccountError(err)) {
        setAuthMode("signin");
        setSignInError("An account with this email already exists. Sign in to use it.");
      } else if (authMode === "signin") {
        setSignInError("That email and password didn't match an account. Please try again.");
      } else {
        setSignInError("We couldn't create your account. Please try again.");
      }
    }
    setEmailSubmitting(false);
  }

  async function checkSubscriptionStatus(currentSession: Session): Promise<boolean | null> {
    const { data, error } = await createClient()
      .from("profiles")
      .select("subscription_active, subscription_tier")
      .eq("id", currentSession.user.id)
      .maybeSingle();

    if (error) {
      console.warn("[twofold] could not read subscription status", error.message);
      setSubscribedTier(null);
      return null;
    }

    if (!data?.subscription_active) {
      setSubscribedTier(null);
      return false;
    }

    // An active subscription with an unrecognised tier still counts as active. The badge is
    // cosmetic; the boolean is what guards the charge.
    const tier = data.subscription_tier?.trim().toLowerCase();
    setSubscribedTier(tier === "premium" ? "Premium" : tier === "plus" ? "Plus" : null);
    return true;
  }

  useEffect(() => {
    let cancelled = false;

    (async () => {
      const initialSession = await getSession();
      if (cancelled) return;
      setSession(initialSession);
      setAuthLoading(false);

      if (initialSession) {
        const alreadySubscribed = await checkSubscriptionStatus(initialSession);
        if (cancelled) return;

        // Resume a purchase that was interrupted by the Apple sign-in redirect.
        //
        // Only on a positive "they have nothing". `null` is an unread status, and resuming a
        // checkout on the strength of a failed lookup is how an existing subscriber gets billed a
        // second time — the one outcome here nobody can undo from this page.
        if (!attemptedPendingResume.current) {
          attemptedPendingResume.current = true;
          const pending = sessionStorage.getItem(PENDING_KEY);
          if (pending && alreadySubscribed === false) {
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
              checkout"), so it's simply untrue once there's a session. The "Signed in as …" line
              below replaces it, and says which account. Gated on !authLoading as well so a
              signed-in visitor never sees it flash on first paint.

              It named Apple until the sign-in step stopped forcing it. Naming one provider was the
              visible half of a bug that cost people money: a Google or email account holder who
              signed in with Apple got a second Supabase user, and their subscription attached to it.

              It then said "the same account you use in the app", which assumed a reader who already
              has one. Most people reading this page do not: anyone who installs the app first meets
              a non-dismissable paywall during onboarding and subscribes there. The two groups this
              page actually serves are people who found the site before the app, and people who quit
              at that paywall — see migration 20261110001200, which exists because that is the most
              likely place to stop. So it describes making an account, and treats already having one
              as the other case rather than the assumed one. */}
          {!authLoading && !session && (
            <div className="apple-note">
              <svg className="icon">
                <use href="/assets/icons.svg#icon-check-circle" />
              </svg>
              You&apos;ll create your Twofold account at checkout - the same one you&apos;ll sign in
              with when you download the app.
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
          ) : signInFor ? (
            /* The sign-in step, shown in place of the cards once a plan is picked. It replaces an
               immediate redirect to Apple — see attemptPurchase for why that was the wrong default.

               All three of the app's methods are here, and that is the point rather than a nicety.
               Apple and Google alone would have no correct option for somebody whose Twofold account
               is an email address, and those people are disproportionately who this page is for: an
               account is created at `.saveAccount`, *before* the onboarding paywall, so anyone who
               quit at that paywall already has one. For them a provider button is not a login, it is
               a second account and a stranded subscription.

               Create is the default because most people here have no account at all — anyone who
               installed the app first subscribed during onboarding. */
            <div className="card waitlist-card" style={{ marginTop: 12, maxWidth: 460, marginLeft: "auto", marginRight: "auto", textAlign: "left" }}>
              <h3 style={{ marginBottom: 6 }}>
                {authMode === "create" ? "Create your account" : "Sign in"}
              </h3>
              <p style={{ marginBottom: 20 }}>
                {authMode === "create"
                  ? "Your subscription lives on this account, and it's what you'll sign in with when you download the app."
                  : "Use the account you already have in Twofold, so your subscription reaches it rather than a new one."}
              </p>

              <button
                type="button"
                className="btn btn-primary"
                style={{ width: "100%", marginBottom: 8 }}
                disabled={oauthPending !== null}
                onClick={() => startOAuth("apple")}
              >
                {oauthPending === "apple" ? "Opening…" : "Continue with Apple"}
              </button>
              <button
                type="button"
                className="btn btn-ghost"
                style={{ width: "100%", marginBottom: 16 }}
                disabled={oauthPending !== null}
                onClick={() => startOAuth("google")}
              >
                {oauthPending === "google" ? "Opening…" : "Continue with Google"}
              </button>

              <p style={{ textAlign: "center", fontSize: "0.85em", opacity: 0.7, marginBottom: 12 }}>or</p>

              <form className="auth-form" onSubmit={submitEmailAuth} noValidate>
                {authMode === "create" && (
                  <>
                    <label className="sr-only" htmlFor="signup-first-name">First name</label>
                    <input
                      id="signup-first-name"
                      name="given-name"
                      type="text"
                      autoComplete="given-name"
                      placeholder="First name"
                      value={firstName}
                      onChange={(event) => setFirstName(event.target.value)}
                    />
                  </>
                )}

                <label className="sr-only" htmlFor="signup-email">Email address</label>
                <input
                  id="signup-email"
                  name="email"
                  type="email"
                  inputMode="email"
                  autoComplete="email"
                  placeholder="yourname@email.com"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                />

                <label className="sr-only" htmlFor="signup-password">Password</label>
                <input
                  id="signup-password"
                  name="password"
                  type="password"
                  autoComplete={authMode === "create" ? "new-password" : "current-password"}
                  placeholder="Password"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                />

                {authMode === "create" && (
                  <>
                    <label className="sr-only" htmlFor="signup-confirm">Confirm password</label>
                    <input
                      id="signup-confirm"
                      name="confirm-password"
                      type="password"
                      autoComplete="new-password"
                      placeholder="Confirm password"
                      value={confirmPassword}
                      onChange={(event) => setConfirmPassword(event.target.value)}
                    />

                    {/* Says which rule is unmet rather than only disabling the button, because a
                        dead button with no reason is the same dead end as no button. */}
                    {password !== "" && (
                      <p style={{ fontSize: "0.85em", opacity: 0.8, marginBottom: 8 }}>
                        Password strength: {passwordStrengthLabel(password)}
                        {!isStrongEnough(password) && " — use at least 8 characters"}
                      </p>
                    )}
                    {confirmPassword !== "" && confirmPassword !== password && (
                      <p style={{ fontSize: "0.85em", opacity: 0.8, marginBottom: 8 }}>
                        Those passwords don&apos;t match.
                      </p>
                    )}

                    {/* The same gate the app puts on every route off SaveAccountView, and the same
                        sentence, so the thing being agreed to does not depend on where you signed
                        up. */}
                    <label style={{ display: "flex", gap: 8, alignItems: "flex-start", fontSize: "0.85em", marginBottom: 16 }}>
                      <input
                        type="checkbox"
                        checked={acceptedTerms}
                        onChange={(event) => setAcceptedTerms(event.target.checked)}
                        style={{ marginTop: 3 }}
                      />
                      <span>
                        I&apos;m 16 or over, and I agree to the <a href="/terms">Terms of Use</a> and{" "}
                        <a href="/privacy">Privacy Policy</a>.
                      </span>
                    </label>
                  </>
                )}

                <button
                  type="submit"
                  className="btn btn-primary"
                  style={{ width: "100%" }}
                  disabled={!canSubmitEmail || emailSubmitting}
                >
                  {emailSubmitting
                    ? "One moment…"
                    : authMode === "create"
                      ? "Create account"
                      : "Sign in"}
                </button>
              </form>

              {signInError && (
                <p className="form-status" data-state="error" role="status" aria-live="polite">
                  {signInError}
                </p>
              )}

              <div style={{ marginTop: 16, textAlign: "center" }}>
                <button
                  type="button"
                  className="text-link"
                  style={{ background: "none", border: "none", cursor: "pointer" }}
                  onClick={() => {
                    setAuthMode(authMode === "create" ? "signin" : "create");
                    setSignInError(null);
                  }}
                >
                  {authMode === "create"
                    ? "Already have a Twofold account? Sign in"
                    : "Need an account? Create one"}
                </button>
              </div>

              <div style={{ marginTop: 10, textAlign: "center" }}>
                <button
                  type="button"
                  className="text-link"
                  style={{ background: "none", border: "none", cursor: "pointer" }}
                  onClick={() => setSignInFor(null)}
                >
                  Back to plans
                </button>
              </div>
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
