// The support console's write path: the things it cannot do from the browser.
//
// Everything else the console does is a security-definer RPC called with the admin's own session
// under RLS. Three things are not reachable that way, and they are why this exists:
//
//   * Soft-deleting an `auth.users` row needs `auth.admin.deleteUser`, which needs the service key.
//   * Cancelling a web subscription needs RevenueCat and Stripe credentials.
//   * Both must happen in one order, with a failure in the first stopping the second.
//
// ---------------------------------------------------------------------------
// Why the service key lives here and not in the website
// ---------------------------------------------------------------------------
//
// The obvious alternative is a Next.js Server Action holding SUPABASE_SERVICE_ROLE_KEY. That would
// put a key that bypasses every RLS policy into the same deployment that serves anonymous
// marketing pages, and it would need a second implementation of the Stripe cancellation that
// `_shared/subscription-cancel.ts` already has. Here the key stays in Supabase secrets and the
// cancellation logic has one copy, shared with `delete-account`.
//
// ---------------------------------------------------------------------------
// Two clients, deliberately
// ---------------------------------------------------------------------------
//
// `userClient` carries the caller's JWT and is used for exactly one thing: asking the database
// whether they hold the support role. `serviceClient` does the work. Checking authorisation with
// the privileged client is the mistake that makes the whole gate ornamental — it would answer for
// the service role, which is an admin by construction.
//
// Every action requires a reason. Not because anybody reads them routinely, but because an
// unexplained destructive action found in the log in two years is indistinguishable from a mistake.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { cancelWebSubscriptions } from "../_shared/subscription-cancel.ts";

interface Body {
  action?: string;
  profileId?: string;
  coupleId?: string;
  reason?: string;
}

function bad(message: string, status = 400): Response {
  return Response.json({ error: message }, { status });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return bad("Method not allowed", 405);

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return bad("Invalid request");
  }

  const reason = (body.reason ?? "").trim();
  if (reason.length < 3) return bad("A reason is required.");
  if (reason.length > 500) return bad("That reason is too long.");

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );

  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return bad("Not authenticated", 401);

  // Asked of the database rather than inferred from anything in the request. The role lives in
  // `feedback_admins` and `is_support_admin()` reads it under the caller's own JWT.
  const { data: isSupportAdmin } = await userClient.rpc("is_support_admin");
  if (isSupportAdmin !== true) return bad("Not authorised", 403);

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  if (body.action === "account.delete") {
    return await deleteAccount(serviceClient, user.id, body.profileId ?? "", reason);
  }

  if (body.action === "subscription.cancel") {
    return await cancelSubscription(serviceClient, user.id, body.profileId ?? "", reason);
  }

  return bad("Unknown action");
});

/// Deleting somebody else's account, in the same order and with the same refusal as
/// `delete-account` does for its own caller.
async function deleteAccount(
  // deno-lint-ignore no-explicit-any
  serviceClient: any,
  actorId: string,
  profileId: string,
  reason: string,
): Promise<Response> {
  if (!profileId) return bad("No account given.");

  // ---------------------------------------------------------------------------
  // Step 0: cancel a web subscription, and refuse to delete if that fails
  // ---------------------------------------------------------------------------
  //
  // Exactly `delete-account`'s reasoning, and it applies more strongly here: after this runs the
  // person has no account to sign in to and no Settings screen, and unlike a self-serve deletion
  // they are not even present to notice. A deletion that did not happen is an inconvenience
  // somebody can retry; a live subscription against an account nobody can sign in to is a charge
  // they cannot stop. Of the two ways to be wrong, only one takes money.
  //
  // `immediately`, not at period end — the same choice delete-account makes, and for the same
  // reason: the access an end-of-period cancellation would preserve is access to an app the person
  // can no longer sign in to.
  let cancelled = 0;
  const revenueCatKey = Deno.env.get("REVENUECAT_REST_API_KEY");
  if (!revenueCatKey) {
    console.error("[admin-actions] REVENUECAT_REST_API_KEY is not set");
    return bad(
      "We can't tell whether this account has a web subscription, so it hasn't been deleted. " +
        "Deleting it while a subscription is live would keep charging them.",
      503,
    );
  }

  try {
    cancelled = await cancelWebSubscriptions(profileId, {
      revenueCatKey,
      stripeKey: Deno.env.get("STRIPE_SECRET_KEY"),
      mode: "immediately",
    });
  } catch (err) {
    console.error("[admin-actions] could not cancel web subscription:", (err as Error).message);
    return bad(
      "Couldn't cancel this account's subscription, so it hasn't been deleted. Try again, or " +
        "cancel the subscription first.",
      503,
    );
  }

  // Step 1: scrub. Checks the support role again inside — this is called with the service client,
  // so that check passes trivially, but it also writes the audit row with the reason.
  const { error: scrubError } = await serviceClient.rpc("admin_scrub_account", {
    p_profile_id: profileId,
    p_reason: reason,
  });
  if (scrubError) {
    console.error("[admin-actions] admin_scrub_account failed:", scrubError.message);
    return bad("Couldn't delete this account's data. Please try again.", 500);
  }

  // Step 2: soft-delete the auth row. `shouldSoftDelete: true` sets deleted_at and leaves the row
  // in place — a hard delete cascades through profiles and would take the OTHER partner's shared
  // history with it.
  const { error: authError } = await serviceClient.auth.admin.deleteUser(profileId, true);
  if (authError) {
    console.error("[admin-actions] deleteUser failed:", authError.message);
    // Step 1 already happened. Re-running is safe — both steps are idempotent — so this says so
    // rather than implying nothing was done.
    return bad(
      "Their data was deleted but disabling sign-in failed. Run this again — it's safe to repeat.",
      500,
    );
  }

  await serviceClient.rpc("admin_record_action", {
    p_actor: actorId,
    p_action: "account.delete",
    p_subject: profileId,
    p_reason: reason,
    p_details: { cancelled_subscriptions: cancelled },
  });

  return Response.json({ ok: true, cancelledSubscriptions: cancelled });
}

/// Cancelling somebody's web subscription without deleting anything. At period end, because they
/// are keeping their account and have paid through a date that Stripe will not refund.
async function cancelSubscription(
  // deno-lint-ignore no-explicit-any
  serviceClient: any,
  actorId: string,
  profileId: string,
  reason: string,
): Promise<Response> {
  if (!profileId) return bad("No account given.");

  const revenueCatKey = Deno.env.get("REVENUECAT_REST_API_KEY");
  if (!revenueCatKey) return bad("Billing provider is not configured.", 503);

  let cancelled = 0;
  try {
    cancelled = await cancelWebSubscriptions(profileId, {
      revenueCatKey,
      stripeKey: Deno.env.get("STRIPE_SECRET_KEY"),
      mode: "at_period_end",
    });
  } catch (err) {
    console.error("[admin-actions] could not cancel subscription:", (err as Error).message);
    return bad("Couldn't cancel that subscription. Nothing has changed.", 503);
  }

  // Zero means there was nothing of ours to cancel — an App Store subscription, which Apple gives
  // no way to end for somebody else. Reported plainly rather than as success, so nobody tells a
  // customer a charge has stopped when it has not.
  await serviceClient.rpc("admin_record_action", {
    p_actor: actorId,
    p_action: cancelled > 0 ? "subscription.cancel" : "subscription.cancel.nothing_to_do",
    p_subject: profileId,
    p_reason: reason,
    p_details: { cancelled },
  });

  return Response.json({ ok: true, cancelled });
}

/* To invoke locally:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/admin-actions' \
    --header 'Authorization: Bearer <support admin access token>' \
    --header 'Content-Type: application/json' \
    --data '{"action":"subscription.cancel","profileId":"<uuid>","reason":"they emailed asking"}'

*/
