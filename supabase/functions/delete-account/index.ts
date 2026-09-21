// Self-serve account deletion. Requires an `Authorization: Bearer <user access token>` header
// (the caller's own Supabase auth session) — deletes only the calling user's own account, never
// anyone else's.
//
// Takes no body. It used to accept `{ "deleteSharedData": true }`, which asked
// `delete_own_account` to purge every shared archive this user belonged to. That parameter has
// ignored its argument since 20261005000000_purge_is_only_ever_the_timer.sql made the 90-day
// archive clock the only route by which shared data is ever deleted, so the flag was promising
// something no code did — it is gone from the app (see `DeleteAccountView`) and no longer read
// here. Older installed builds may still POST it; an unknown field in the body is simply
// ignored, and their behaviour is unchanged because the RPC was already discarding it.
//
// Two-step, in this order:
//   1. `delete_own_account()` (security definer RPC, runs as the caller)
//      scrubs this user's own identifying profile fields and storage objects, and dissolves any
//      couple they're still actively part of — see that migration's own header comment for
//      exactly why this doesn't just hard-delete the profile row outright (short version: the FK
//      cascade from profiles to couples would wipe the *other* partner's shared history too).
//   2. `auth.admin.deleteUser(id, shouldSoftDelete: true)` — soft-deletes the actual `auth.users`
//      row: sign-in is permanently disabled and the account can never be recovered, but the row
//      itself is left in place (`deleted_at` set, not actually removed), so it never triggers
//      that same FK cascade. This step needs the service-role key, which is why it has to happen
//      here rather than directly from the client.
//
// If step 1 succeeds but step 2 fails, the account is left "scrubbed but still able to sign in" —
// the client should treat any error from this function as "please try again" rather than
// assuming nothing happened, and re-calling this function is always safe (both steps are
// idempotent).
//
// ---------------------------------------------------------------------------
// Step 0: cancel a web subscription, and refuse to delete if that fails
// ---------------------------------------------------------------------------
//
// Runs before either step, because after them there is nothing left to act on and no way for the
// person to come back and fix it themselves. An App Store subscription is not ours to cancel and
// is skipped (`isStoreManaged`) — Apple offers no mechanism, which is why `DeleteAccountView`
// warns and links to Apple's own subscription settings.
//
// A website subscription is ours, billed through Stripe with credentials we hold, and once the
// account is gone the buyer has no Settings screen for it and no way to sign in and find it. The
// FAQ promises we will cancel it if they email us; this does it without their having to know that.
//
// A failure here aborts the deletion rather than proceeding without it. That is the deliberate
// choice: a deletion that did not happen is an inconvenience the person can retry, and a live
// subscription against an account nobody can sign in to is a charge they cannot stop. Of the two
// ways to be wrong, only one takes money.

import { createClient } from "jsr:@supabase/supabase-js@2";
// `cancelWebSubscriptions` used to live in this file. It moved to _shared when the account portal
// needed the same operation: two copies of the logic that decides whether somebody keeps being
// charged is exactly the pair that agrees in testing and disagrees in production.
//
// Note the mode. Deletion cancels `immediately`, which is right only here — the access an
// end-of-period cancellation would preserve is access to an app the person can no longer sign in
// to. The portal passes `at_period_end`, because somebody who is staying has paid through a date
// and Stripe refunds none of it.
import { cancelWebSubscriptions } from "../_shared/subscription-cancel.ts";
import { serveWithCors } from "../_shared/cors.ts";

Deno.serve(serveWithCors(async (req) => {
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

  let cancelledSubscriptions = 0;
  try {
    const revenueCatKey = Deno.env.get("REVENUECAT_REST_API_KEY");
    if (!revenueCatKey) {
      // Without it we cannot even tell whether there is a web subscription, and "assume there
      // isn't" is the assumption that charges people.
      throw new Error("REVENUECAT_REST_API_KEY is not set");
    }
    cancelledSubscriptions = await cancelWebSubscriptions(user.id, {
      revenueCatKey,
      stripeKey: Deno.env.get("STRIPE_SECRET_KEY"),
      mode: "immediately",
    });
  } catch (err) {
    // Deliberately before any deletion, and deliberately fatal. Nothing has been scrubbed yet, so
    // the account is exactly as it was and the retry the client is told to make is a clean one.
    //
    // No subscription id, customer id or key in the log line — the message is ours, and the user
    // id is omitted the same way `revenuecat-webhook` omits it.
    console.error("[delete-account] could not cancel web subscription:", (err as Error).message);
    return Response.json(
      {
        error:
          "We couldn't cancel your subscription just now, so we haven't deleted your account — " +
          "deleting it while the subscription is live would keep charging you. Please try again, " +
          "or email support@twofoldapp.com.au.",
      },
      { status: 503 },
    );
  }

  // No arguments: `p_delete_shared_data` defaults to false and is ignored either way. Any body
  // an older build sends goes unread.
  const { error: rpcError } = await userClient.rpc("delete_own_account", {});
  if (rpcError) {
    console.error("[delete-account] delete_own_account failed:", rpcError.message);
    return Response.json({ error: "Couldn't delete your account data. Please try again." }, { status: 500 });
  }

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { error: authError } = await serviceClient.auth.admin.deleteUser(user.id, true);
  if (authError) {
    console.error("[delete-account] auth.admin.deleteUser failed:", authError.message);
    return Response.json({ error: "Your data was deleted but signing out failed — please try again." }, { status: 500 });
  }

  return Response.json({ ok: true, cancelledSubscriptions });
}));

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/delete-account' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --header 'Authorization: Bearer <user-access-token>'

*/
