// Re-asks RevenueCat what it thinks about every subscriber we believe is active, and applies the
// answer. Cron entrypoint — see the migration that schedules it.
//
// ---------------------------------------------------------------------------
// Why this exists
// ---------------------------------------------------------------------------
//
// Every subscription column on `profiles` is written by webhook delivery alone. There is no other
// path: `subscription_checked_at` guards against a *stale* write landing after a fresher one, but
// nothing ever re-reads RevenueCat, so a delivery that is missed, dropped, or never sent leaves a
// row wrong permanently — until that subscriber happens to generate another event. A lapse that
// never arrives keeps someone's access alive; a renewal that never arrives paywalls someone who is
// paying. Neither self-corrects, and neither is visible from inside the app.
//
// So this asks again, nightly. It is the difference between a system that is eventually consistent
// and one that is consistent only if the network was never unkind.
//
// ---------------------------------------------------------------------------
// Why it posts to the webhook rather than doing the work itself
// ---------------------------------------------------------------------------
//
// `revenuecat-webhook` already does exactly this job: read the subscriber from RevenueCat, apply
// the state behind the freshness guard, record the outcome in `subscription_events`. Duplicating
// that here would mean two paths that decide entitlement, which is the kind of pair that agrees
// until the day it doesn't — and the one that runs unattended at 3am would be the one nobody
// notices has drifted.
//
// It cannot simply be imported: that module calls `Deno.serve` at import time, which is the same
// reason `subscriber.ts` was split out of it for testing. Rather than refactor the live
// entitlement writer to add a caller, this reaches it the way RevenueCat does, with a synthetic
// event. One apply path, exercised identically whether the trigger was a real purchase or this.
//
// The events it writes are recorded as `RECONCILE` in `subscription_events`, so a run of
// corrections is distinguishable from genuine deliveries when reading that ledger later.

import { createClient } from "jsr:@supabase/supabase-js@2";

/// Who gets re-checked.
///
/// Everyone currently believed active, plus anyone the webhook has written about recently. The
/// second half is the more important one and the less obvious: a profile that reads inactive may
/// be a lapse we recorded correctly, or a renewal we never heard about — and only the second is a
/// paying customer being locked out. Checking a window of recently-touched rows catches that
/// without re-reading every profile that ever held a subscription.
const RECENTLY_TOUCHED_DAYS = 45;

/// Sequential, with a pause between subscribers. RevenueCat rate-limits, this is a background job
/// that nobody is waiting on, and a burst that trips a 429 would reconcile fewer people than a slow
/// loop that trips nothing.
const PAUSE_BETWEEN_MS = 250;

interface ProfileRow {
  id: string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  // Same shape as every other cron entrypoint here: the service role key is the credential, and a
  // stray public request must not be able to trigger a run against the provider.
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const presented = req.headers.get("Authorization");
  if (!serviceKey || presented !== `Bearer ${serviceKey}`) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  const webhookSecret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
  const projectUrl = Deno.env.get("SUPABASE_URL");
  if (!webhookSecret || !projectUrl) {
    console.error("[reconcile-subscriptions] REVENUECAT_WEBHOOK_SECRET or SUPABASE_URL is not set");
    return Response.json({ error: "Not configured" }, { status: 500 });
  }

  const serviceClient = createClient(projectUrl, serviceKey);

  const cutoff = new Date(Date.now() - RECENTLY_TOUCHED_DAYS * 24 * 60 * 60 * 1000).toISOString();
  const { data: profiles, error } = await serviceClient
    .from("profiles")
    .select("id")
    .or(`subscription_active.eq.true,subscription_checked_at.gte.${cutoff}`);

  if (error) {
    console.error("[reconcile-subscriptions] failed to load profiles:", error.message);
    return Response.json({ error: "Failed to load profiles" }, { status: 500 });
  }

  const ids = (profiles ?? []).map((p) => (p as ProfileRow).id);
  let reconciled = 0;
  let failed = 0;

  for (const id of ids) {
    try {
      const response = await fetch(`${projectUrl}/functions/v1/revenuecat-webhook`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: webhookSecret },
        // `app_user_id` uppercased to match what RevenueCat itself sends — Swift's
        // `UUID.uuidString` is what `Purchases.logIn` was given, and the webhook normalises it
        // back down. Sending the lowercase form would work too; sending what the real thing sends
        // means this path is never the one exercising a different branch.
        body: JSON.stringify({
          api_version: "1.0",
          event: { type: "RECONCILE", app_user_id: id.toUpperCase() },
        }),
      });
      if (response.ok) {
        reconciled += 1;
      } else {
        // A 5xx here is the webhook's own "transient, retry me" — which for us just means this
        // subscriber missed tonight and gets another chance tomorrow. Nothing to escalate.
        failed += 1;
        console.warn(`[reconcile-subscriptions] ${id}: webhook returned ${response.status}`);
      }
    } catch (err) {
      failed += 1;
      console.error(`[reconcile-subscriptions] ${id} threw:`, (err as Error).message);
    }
    await new Promise((resolve) => setTimeout(resolve, PAUSE_BETWEEN_MS));
  }

  console.log(`[reconcile-subscriptions] checked ${ids.length}, reconciled ${reconciled}, failed ${failed}`);
  return Response.json({ checked: ids.length, reconciled, failed });
});

/* To invoke locally:

  1. Run `supabase start`
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/reconcile-subscriptions' \
    --header 'Authorization: Bearer <service-role-key>'

*/
