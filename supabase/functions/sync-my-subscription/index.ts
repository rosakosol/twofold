// Asks RevenueCat about the caller, right now, and applies the answer.
//
// ---------------------------------------------------------------------------
// Why this exists
// ---------------------------------------------------------------------------
//
// `subscription_active` is written by webhook delivery alone. Between a purchase completing on the
// device and that webhook arriving, a genuine subscriber's row says false. The app has always
// papered over that gap client-side by ORing in RevenueCat's own receipt-validated answer
// (`deviceHoldsEntitlement` in RootView), which was enough while the row only decided which screen
// to show.
//
// It stopped being enough with 20261028000000, which put the subscription check into RLS. Policies
// cannot see RevenueCat — they see the row. So the gap turned from cosmetic into blocking: somebody
// who has just paid could be unable to create anything until the webhook showed up, and that
// webhook is the same delivery mechanism that silently failed for every paid streak repair until
// 20261026000100.
//
// `reconcile-subscriptions` does not close it either. That job selects profiles that are already
// `subscription_active` or recently checked, so a *first* purchase is not even in its set.
//
// ---------------------------------------------------------------------------
// Why it posts to the webhook rather than doing the work itself
// ---------------------------------------------------------------------------
//
// Same reasoning as `reconcile-subscriptions`, which does exactly this: `revenuecat-webhook`
// already reads the subscriber from RevenueCat, applies the state behind its freshness guard, and
// records the outcome. A second path that decided entitlement would be the kind of pair that agrees
// in testing and disagrees in production, about money.
//
// ---------------------------------------------------------------------------
// Why a client may call it at all
// ---------------------------------------------------------------------------
//
// It reconciles the caller and nobody else: the id comes from their own verified JWT, never from
// the body. The answer comes from RevenueCat, not from the app — this is a request to go and look,
// not an assertion about what will be found, so it grants nothing a client could not already have
// had by waiting for the webhook. What it changes is how long the waiting takes.
//
// Rate limited because it reaches a third-party API on demand. Six an hour is far more than the
// one call a purchase needs, and far less than a loop.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { enforceRateLimit } from "../_shared/rate-limit.ts";

const RATE_LIMIT = { bucket: "sync-my-subscription", limit: 6, window: "1 hour" };

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  const projectUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const webhookSecret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
  if (!projectUrl || !serviceKey || !webhookSecret) {
    console.error("[sync-my-subscription] SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY or REVENUECAT_WEBHOOK_SECRET is not set");
    return Response.json({ error: "Not configured" }, { status: 500 });
  }

  const userClient = createClient(
    projectUrl,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );

  const { data: { user } } = await userClient.auth.getUser();
  if (!user) {
    return Response.json({ error: "Not authenticated" }, { status: 401 });
  }

  const limited = await enforceRateLimit(userClient, RATE_LIMIT);
  if (limited) return limited;

  // `app_user_id` uppercased to match what RevenueCat itself sends — see the same note in
  // `reconcile-subscriptions`. Taken from the verified session, never from the request body: a
  // caller must not be able to name somebody else here.
  const response = await fetch(`${projectUrl}/functions/v1/revenuecat-webhook`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: webhookSecret },
    body: JSON.stringify({
      api_version: "1.0",
      event: { type: "RECONCILE", app_user_id: user.id.toUpperCase() },
    }),
  });

  if (!response.ok) {
    // The webhook's own "transient, retry me". Reported as such rather than as a failed purchase:
    // nothing is lost, the nightly job will catch it, and the caller can try again.
    console.warn(`[sync-my-subscription] webhook returned ${response.status}`);
    return Response.json({ error: "Couldn't check with the store just now." }, { status: 503 });
  }

  // Read the row back rather than trusting the webhook's response shape, so the caller is told what
  // is actually true of them now — which is the only thing RLS will agree with.
  const serviceClient = createClient(projectUrl, serviceKey);
  const { data: profile } = await serviceClient
    .from("profiles")
    .select("subscription_active, subscription_tier")
    .eq("id", user.id)
    .single();

  return Response.json({
    active: profile?.subscription_active ?? false,
    tier: profile?.subscription_tier ?? null,
  });
});
