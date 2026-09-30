"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import type { Session } from "@supabase/supabase-js";
import { APP_STORE_URL, PLANS } from "@/lib/marketing/config";
import type { ResolvedPlan } from "@/lib/marketing/sanity";
import { getSession, onAuthChange, signInWithProvider } from "@/lib/marketing/auth";
import {
  EmailPasswordForm,
  type EmailPasswordMode,
} from "@/components/auth/EmailPasswordForm";
import {
  PasswordResetPanel,
  passwordResetCopy,
  type PasswordResetStage,
} from "@/components/auth/PasswordResetPanel";
import { providerFallbackName, providerLabel, sessionProvider } from "@/lib/marketing/provider";
import { signOutAndGoHome } from "@/lib/auth/signOutAndGoHome";
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

/**
 * The submit button EmailPasswordForm wears on this page: marketing.css's own primary pill, full
 * width, the way every other button here is drawn. Module scope rather than inline, so switching
 * modes does not unmount and remount the form (and empty the fields) on every render.
 */
function MarketingSubmit(props: React.ComponentProps<"button">) {
  return <button {...props} className="btn btn-primary" style={{ width: "100%" }} />;
}

/** The text link the shared reset panel gets back out through, drawn like every other one here. */
function MarketingBackLink(props: React.ComponentProps<"button">) {
  return (
    <button
      type="button"
      {...props}
      className="text-link"
      style={{ background: "none", border: "none", cursor: "pointer" }}
    />
  );
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
  const [authMode, setAuthMode] = useState<EmailPasswordMode>("create");
  // Whether the card is asking for a recovery email instead of a password. The one state the
  // checkout genuinely shares with the board's sign-in page, and it was missing here: an account
  // exists from `.saveAccount` onwards, *before* the onboarding paywall, so somebody who quit at
  // that paywall and came here to buy is exactly who arrives holding a password they may not
  // remember — and "That email and password didn't match an account" was the end of the road.
  const [resetStage, setResetStage] = useState<PasswordResetStage>("off");
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

  /// Picks a purchase back up after the sign-in that interrupted it.
  ///
  /// Called from both places a session can arrive, which is the fix for a real bug: this used to
  /// live only in the mount path. That path exists for the Apple and Google redirects, which
  /// reload the page — so it ran for them and never for an email and password sign-in, which
  /// changes the session in place without a reload. Signing in that way left somebody looking at
  /// a page that had plainly accepted their login and then done nothing with the plan they had
  /// already chosen. Refreshing by hand took them straight to checkout, because that is the path
  /// this was on.
  ///
  /// Resumes only on a positive "they have nothing". `null` is an unread status, and resuming a
  /// checkout on the strength of a failed lookup is how an existing subscriber gets billed twice —
  /// the one outcome on this page nobody can undo.
  async function resumePendingPurchase(currentSession: Session) {
    // Read and claim before the first `await`, not after.
    //
    // Both callers can fire for one sign-in — a redirect lands with a session *and* raises an auth
    // change — and an `await` between the check and the claim is a window where both pass it. Two
    // resumes is two checkouts, which is the outcome this whole function is careful about. The
    // claim is synchronous, so the second caller finds it already taken.
    const pending = sessionStorage.getItem(PENDING_KEY);
    const mine = pending !== null && !attemptedPendingResume.current;
    if (mine) attemptedPendingResume.current = true;

    // Runs either way: it is what fills in "you're already on Premium" for somebody who arrived
    // with a session and no pending plan.
    const alreadySubscribed = await checkSubscriptionStatus(currentSession);
    if (!mine || !pending) return;

    // Only on a positive "they have nothing". `null` is an unread status, and resuming a checkout
    // on the strength of a failed lookup is how an existing subscriber gets billed a second time.
    if (alreadySubscribed !== false) return;

    sessionStorage.removeItem(PENDING_KEY);
    const { planId, period: pendingPeriod } = JSON.parse(pending) as Pending;
    setPeriod(pendingPeriod);
    attemptPurchase(planId, pendingPeriod);
  }

  useEffect(() => {
    let cancelled = false;

    (async () => {
      const initialSession = await getSession();
      if (cancelled) return;
      setSession(initialSession);
      setAuthLoading(false);
      if (initialSession && !cancelled) await resumePendingPurchase(initialSession);
    })();

    const unsubscribe = onAuthChange((newSession) => {
      setSession(newSession);
      if (newSession) void resumePendingPurchase(newSession);
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

  // Arrive at the top, however you arrived.
  //
  // Two things put people in the middle of this page. The browser restores the scroll position
  // when you come back from an external checkout, so you return to wherever you were when you
  // left — which, since you left by pressing a Buy button, is the middle. And the plan scroll
  // below used `block: "center"`, which puts a card in the centre of the viewport by definition.
  //
  // `scrollRestoration` is a global on `history`, so the previous value is put back on unmount
  // rather than left as "manual" for every other page in the app.
  useEffect(() => {
    const previous = history.scrollRestoration;
    if (previous !== undefined) history.scrollRestoration = "manual";
    window.scrollTo(0, 0);
    return () => {
      if (previous !== undefined) history.scrollRestoration = previous;
    };
  }, []);

  useEffect(() => {
    if (requestedPlan === "premium" || requestedPlan === "plus") {
      // The referring page (e.g. the Home pricing preview) named a specific plan -
      // scroll it into view rather than changing which cards render, since both
      // plans always render together now.
      //
      // `start`, not `center`. Centring is what put somebody following a plan link halfway down
      // the page with the heading scrolled off — and the same effect re-runs on a checkout return
      // that keeps `?plan=` in the URL, undoing the scroll to top above.
      document.getElementById(`plan-${requestedPlan}`)?.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }, [requestedPlan]);

  async function handleSignOut() {
    await signOutAndGoHome();
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
                {resetStage !== "off"
                  ? passwordResetCopy.title
                  : authMode === "create"
                    ? "Create your account"
                    : "Sign in"}
              </h3>
              <p style={{ marginBottom: 20 }}>
                {resetStage === "sent"
                  ? passwordResetCopy.sent
                  : resetStage === "form"
                    ? passwordResetCopy.form
                    : authMode === "create"
                      ? "Your subscription lives on this account, and it's what you'll sign in with when you download the app."
                      : "Use the account you already have in Twofold, so your subscription reaches it rather than a new one."}
              </p>

              {resetStage !== "off" ? (
                /* Shared with /auth/sign-in — see PasswordResetPanel on why the confirmation never
                   says whether that address had an account, and why this is a panel on the card
                   rather than a route: navigating away from here would abandon the plan that was
                   picked, which lives in this tab's sessionStorage. */
                <PasswordResetPanel
                  stage={resetStage}
                  onStageChange={setResetStage}
                  onError={setSignInError}
                  busyLabel="Sending…"
                  sentNote={
                    <p style={{ fontSize: "0.9em" }}>
                      Leave this tab open. Once you&apos;ve set a new password, come back here and
                      sign in &mdash; the {plans[signInFor.planId].name} plan you picked is still waiting,
                      and checkout picks up where it left off.
                    </p>
                  }
                  chrome={{ form: "auth-form", Submit: MarketingSubmit, BackLink: MarketingBackLink }}
                />
              ) : (
                <>
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

                  {/* Shared with /auth/sign-in — see EmailPasswordForm. It reports failures back up
                      rather than rendering them, because the paragraph below is the same one the
                      Apple/Google buttons write to. No `onSuccess`: the session lands via
                      onAuthChange and the pending-plan resume runs from there, which is the path this
                      form's sign-in actually takes (it changes the session in place, with no reload). */}
                  <EmailPasswordForm
                    mode={authMode}
                    onModeChange={setAuthMode}
                    onError={setSignInError}
                    chrome={{ form: "auth-form", Submit: MarketingSubmit }}
                  />

                  <div style={{ marginTop: 16, textAlign: "center" }}>
                    <MarketingBackLink
                      onClick={() => {
                        setAuthMode(authMode === "create" ? "signin" : "create");
                        setSignInError(null);
                      }}
                    >
                      {authMode === "create"
                        ? "Already have a Twofold account? Sign in"
                        : "Need an account? Create one"}
                    </MarketingBackLink>
                  </div>

                  {/* Only on the sign-in side. Offering to reset a password to somebody in the middle
                      of choosing one is noise, and /auth/sign-in and the app's own sign-in screen make
                      the same distinction. */}
                  {authMode === "signin" && (
                    <div style={{ marginTop: 10, textAlign: "center" }}>
                      <MarketingBackLink
                        onClick={() => {
                          setResetStage("form");
                          setSignInError(null);
                        }}
                      >
                        Forgot your password?
                      </MarketingBackLink>
                    </div>
                  )}
                </>
              )}

              {/* Outside the branch: it carries the Apple/Google failures, the shared form's errors
                  and a failed reset request alike, and a reset is the path people reach already
                  locked out — the one place an error must not be swallowed. */}
              {signInError && (
                <p className="form-status" data-state="error" role="status" aria-live="polite">
                  {signInError}
                </p>
              )}

              {/* Hidden while resetting, where the panel's own "Back to sign in" is the way out —
                  two competing back controls on one card is a question, not a route. */}
              {resetStage === "off" && (
                <div style={{ marginTop: 10, textAlign: "center" }}>
                  <MarketingBackLink onClick={() => setSignInFor(null)}>
                    Back to plans
                  </MarketingBackLink>
                </div>
              )}
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
