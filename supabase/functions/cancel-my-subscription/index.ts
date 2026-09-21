// Lets somebody stop their own website subscription renewing, from the account portal — without
// emailing anyone.
//
// The FAQ (20261105000000) currently promises a web subscriber can "email support@twofoldapp.com.au
// and we will cancel it for you". That is a promise kept by hand, only for the people who think to
// ask, and only while somebody is reading that inbox. This is the same promise kept by the person
// who wants it, at the moment they want it.
//
// Requires `Authorization: Bearer <user access token>` and acts only on the caller's own account —
// same gate and same reasoning as `delete-account`, which this deliberately resembles.
//
// ---------------------------------------------------------------------------
// At period end, never immediately
// ---------------------------------------------------------------------------
//
// `delete-account` cancels immediately, and is right to: after it runs there is no account left to
// hold the access. Here the person is staying. They have paid through a date, Stripe refunds
// nothing, and ending it early would take that time away in exchange for nothing.
//
// It also matches the model the rest of the app already shows. `resolveWillRenew` exists because
// cancelling stops the renewal rather than the entitlement, and the app stops nagging someone to
// cancel on the strength of it. This endpoint keeps that true.
//
// ---------------------------------------------------------------------------
// What it will not do
// ---------------------------------------------------------------------------
//
// An App Store subscription is not ours to cancel and never will be — Apple offers developers no
// mechanism. `cancellableSubscriptions` filters those out, so this reports 0 rather than failing,
// and the portal shows Apple's own settings link for that case instead of a button. Reporting
// success for an App Store cancellation would be the worst outcome available: the person believes
// they have stopped a charge that is still coming.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { cancelWebSubscriptions } from "../_shared/subscription-cancel.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );

  const { data: { user } } = await userClient.auth.getUser();
  if (!user) {
    return Response.json({ error: "Not authenticated" }, { status: 401 });
  }

  const revenueCatKey = Deno.env.get("REVENUECAT_REST_API_KEY");
  if (!revenueCatKey) {
    console.error("[cancel-my-subscription] REVENUECAT_REST_API_KEY is not set");
    return Response.json(
      { error: "We couldn't reach our billing provider just now. Please try again shortly." },
      { status: 503 },
    );
  }

  let cancelled = 0;
  try {
    cancelled = await cancelWebSubscriptions(user.id, {
      revenueCatKey,
      stripeKey: Deno.env.get("STRIPE_SECRET_KEY"),
      mode: "at_period_end",
    });
  } catch (err) {
    // No subscription id, customer id or key in the log line — the message is ours, and the user
    // id is omitted the same way `revenuecat-webhook` omits it.
    console.error("[cancel-my-subscription] could not cancel:", (err as Error).message);
    return Response.json(
      {
        error:
          "We couldn't cancel your subscription just now, so nothing has changed — you're still " +
          "subscribed. Please try again, or email support@twofoldapp.com.au.",
      },
      { status: 503 },
    );
  }

  // Deliberately NOT writing `subscription_will_renew` here. RevenueCat is the source of truth for
  // entitlement state and `revenuecat-webhook` is its only writer — a second writer racing it is
  // how the freshness guard there stops meaning anything. The cancellation arrives as a webhook
  // within moments; until it does, the portal says the request went through rather than claiming
  // the row already reflects it.
  return Response.json({ ok: true, cancelled });
});

/* To invoke locally:

  1. Run `supabase start`
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/cancel-my-subscription' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --header 'Authorization: Bearer <user-access-token>'

*/
