// Twofold — pricing page orchestration: renders plan pricing from config, gates
// checkout behind "Sign in with Apple" (same Supabase identity as the app), and drives
// the RevenueCat Web Billing purchase flow. See auth.js / billing.js for the wrappers.
//
// Plan (Plus/Premium) is the tab at the top of the page. Whichever plan is selected
// shows two cards side by side — Monthly and Yearly — for that tier, each a fixed
// plan+period pairing (`data-plan` / `data-period` on the card itself, read directly
// off whichever card a "Get ___" button lives in when it's clicked).

import { PLANS } from "/assets/js/config.js";
import { getSession, onAuthChange, signInWithApple, signOut } from "/assets/js/auth.js";
import { fetchOfferings, fetchCustomerInfo, findPackage, purchasePackage, activeEntitlements } from "/assets/js/billing.js";

const PENDING_KEY = "twofold_pending_plan";
let currentPlan = "plus";

const els = {
  planTabs: document.querySelectorAll("[data-plan-tab]"),
  planCards: document.querySelectorAll("[data-plan]"),
  authStatus: document.getElementById("auth-status"),
  buyButtons: document.querySelectorAll("[data-buy]"),
  subscribedBanner: document.getElementById("subscribed-banner"),
  subscribedText: document.getElementById("subscribed-text"),
  successPanel: document.getElementById("purchase-success"),
  pricingGrid: document.getElementById("pricing-grid"),
  planTabsWrap: document.getElementById("plan-tabs"),
};

function renderPrices() {
  els.planCards.forEach((card) => {
    const plan = PLANS[card.dataset.plan];
    const cardPeriod = card.dataset.period === "monthly" ? "monthly" : "yearly";
    if (!plan) return;
    const num = card.querySelector("[data-price]");
    if (num) num.textContent = plan[cardPeriod].priceLabel;
  });
}

function showPlanTab(planId) {
  currentPlan = planId;
  els.planCards.forEach((card) => {
    card.hidden = card.dataset.plan !== planId;
  });
  els.planTabs.forEach((btn) => {
    btn.classList.toggle("is-active", btn.dataset.planTab === planId);
  });
}

els.planTabs.forEach((btn) => {
  btn.addEventListener("click", () => showPlanTab(btn.dataset.planTab));
});

function setAuthStatus(session) {
  if (!els.authStatus) return;
  if (session) {
    const label = session.user.email || "your Apple ID";
    els.authStatus.innerHTML = "";
    const status = document.createElement("span");
    status.className = "auth-status";
    status.innerHTML = `<svg class="icon"><use href="/assets/icons.svg#icon-check-circle"/></svg> Signed in as ${escapeHtml(label)}`;
    const signOutBtn = document.createElement("button");
    signOutBtn.className = "text-link";
    signOutBtn.style.marginLeft = "12px";
    signOutBtn.style.background = "none";
    signOutBtn.style.border = "none";
    signOutBtn.style.cursor = "pointer";
    signOutBtn.textContent = "Sign out";
    signOutBtn.addEventListener("click", async () => {
      await signOut();
      window.location.reload();
    });
    els.authStatus.append(status, signOutBtn);
  } else {
    els.authStatus.innerHTML = `<span class="form-status" data-state="info">You'll sign in with Apple at checkout — it's how we match your web purchase to your Twofold account.</span>`;
  }
}

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}

async function showAlreadySubscribed(tierName) {
  if (!els.subscribedBanner) return;
  els.subscribedText.textContent = `You already have Twofold ${tierName} — open the app and sign in with the same Apple ID to use it.`;
  els.subscribedBanner.hidden = false;
  els.pricingGrid?.setAttribute("aria-hidden", "true");
  els.pricingGrid?.style.setProperty("opacity", "0.4");
  els.pricingGrid?.style.setProperty("pointer-events", "none");
}

/** `buyBtn` is the actual button clicked (or re-derived from a pending post-signin resume). */
async function attemptPurchase(buyBtn) {
  const card = buyBtn.closest("[data-plan]");
  const planId = card?.dataset.plan ?? buyBtn.dataset.buy;
  const period = card?.dataset.period === "monthly" ? "monthly" : "yearly";

  const session = await getSession();
  if (!session) {
    sessionStorage.setItem(PENDING_KEY, JSON.stringify({ planId, period }));
    await signInWithApple();
    return;
  }

  const plan = PLANS[planId];
  const originalLabel = buyBtn.textContent;
  buyBtn.disabled = true;
  buyBtn.textContent = "Opening checkout…";

  try {
    const offering = await fetchOfferings(session.user.id);
    const pkg = offering ? findPackage(offering, plan[period].packageId) : null;

    if (!pkg) {
      // Web Billing not wired up yet (placeholder key / offering not published). Don't
      // dead-end the funnel — steer to the App Store instead of failing silently.
      buyBtn.disabled = false;
      buyBtn.textContent = originalLabel;
      const fallback = document.getElementById("web-checkout-fallback");
      if (fallback) fallback.hidden = false;
      return;
    }

    const { customerInfo } = await purchasePackage(session.user.id, pkg);
    const active = activeEntitlements(customerInfo);
    if (active.length) {
      els.successPanel?.removeAttribute("hidden");
      els.pricingGrid?.style.setProperty("display", "none");
      els.planTabsWrap?.style.setProperty("display", "none");
      els.successPanel?.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  } catch (err) {
    console.warn("[twofold] purchase failed", err);
    buyBtn.disabled = false;
    buyBtn.textContent = originalLabel;
    const status = document.getElementById("purchase-error");
    if (status) {
      status.hidden = false;
      status.textContent = err?.message?.includes("available")
        ? "Web checkout isn't live yet — download the app to subscribe on iOS for now."
        : "Something went wrong with checkout. Please try again.";
    }
  }
}

els.buyButtons.forEach((btn) => {
  btn.addEventListener("click", () => attemptPurchase(btn));
});

async function init() {
  showPlanTab(currentPlan);
  renderPrices();

  const session = await getSession();
  setAuthStatus(session);

  if (session) {
    const customerInfo = await fetchCustomerInfo(session.user.id);
    const active = activeEntitlements(customerInfo);
    if (active.includes(PLANS.premium.entitlement)) {
      showAlreadySubscribed("Premium");
    } else if (active.includes(PLANS.plus.entitlement)) {
      showAlreadySubscribed("Plus");
    }

    const pending = sessionStorage.getItem(PENDING_KEY);
    if (pending && !active.length) {
      sessionStorage.removeItem(PENDING_KEY);
      const { planId, period } = JSON.parse(pending);
      showPlanTab(planId);
      const card = document.querySelector(`[data-plan="${planId}"][data-period="${period}"]`);
      const btn = card?.querySelector("[data-buy]");
      if (btn) attemptPurchase(btn);
    }
  }

  onAuthChange((newSession) => setAuthStatus(newSession));
}

init();
