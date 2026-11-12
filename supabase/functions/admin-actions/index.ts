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
// whether this action may go ahead (`admin_authorize_account_action`: the support role, a recent
// authenticator code, the typed confirmation, the hourly limit, a target who is not an admin).
// `serviceClient` does the work. Checking authorisation with the privileged client is the mistake
// that makes the whole gate ornamental — it would answer for the service role, which is an admin by
// construction.
//
// Every action requires a reason. Not because anybody reads them routinely, but because an
// unexplained destructive action found in the log in two years is indistinguishable from a mistake.
//
// ---------------------------------------------------------------------------
// The audit row comes first
// ---------------------------------------------------------------------------
//
// Cancelling at RevenueCat cannot be undone and happens outside the database, so the log could not
// record it after the fact if the run stopped half way (security review, F10). Each action now
// writes a `.started` row before anything else, and does nothing if that row cannot be written. The
// closing row is checked too: if it fails, the work is done, so the console is told it succeeded
// and the log keeps the `.started` row.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { userSession } from "../_shared/auth.ts";
import { cancelWebSubscriptions } from "../_shared/subscription-cancel.ts";
import { serveWithCors } from "../_shared/cors.ts";

interface Body {
  action?: string;
  profileId?: string;
  coupleId?: string;
  reason?: string;
  confirmation?: string;
}

function bad(message: string, status = 400): Response {
  return Response.json({ error: message }, { status });
}

/// One audit row. True if it was written.
async function record(
  // deno-lint-ignore no-explicit-any
  serviceClient: any,
  row: { actor: string; action: string; subject: string; reason: string; details?: Record<string, unknown> },
): Promise<boolean> {
  const { error } = await serviceClient.rpc("admin_record_action", {
    p_actor: row.actor,
    p_action: row.action,
    p_subject: row.subject,
    p_reason: row.reason,
    p_details: row.details ?? null,
  });
  if (error) console.error(`[admin-actions] could not write the ${row.action} audit row:`, error.message);
  return !error;
}

const NOT_RECORDED = "Couldn't record this action in the audit log, so nothing has changed. Please try again.";

Deno.serve(serveWithCors(async (req) => {
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

  const { userClient, user } = await userSession(req);
  if (!user) return bad("Not authenticated", 401);

  if (!body.profileId) return bad("No account given.");

  // Asked of the database rather than inferred from anything in the request. It refuses in sentences
  // written for the person at the console, so they are passed on.
  const { error: refused } = await userClient.rpc("admin_authorize_account_action", {
    p_action: body.action ?? "",
    p_profile_id: body.profileId,
    p_reason: reason,
    p_confirmation: body.confirmation ?? null,
  });
  if (refused) {
    const status = ({ "42501": 403, "22023": 400, "P0001": 429 } as Record<string, number>)[refused.code ?? ""];
    if (status) return bad(refused.message, status);
    console.error("[admin-actions] could not check this action:", refused.message);
    return bad("Couldn't check that action. Nothing has changed.", 500);
  }

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
}));

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
  // At period end, like every other caller — RevenueCat's cancel endpoint has no immediate mode, and
  // ending one on the spot means refunding it, which is not a decision an admin deletion should make
  // silently. Stopping the renewal is what prevents the charge; the paid period running out against
  // a deleted account costs nobody anything.
  let cancelled = 0;
  const v2Key = Deno.env.get("REVENUECAT_V2_API_KEY");
  const projectId = Deno.env.get("REVENUECAT_PROJECT_ID");
  if (!v2Key || !projectId) {
    console.error("[admin-actions] REVENUECAT_V2_API_KEY or REVENUECAT_PROJECT_ID is not set");
    return bad(
      "We can't tell whether this account has a web subscription, so it hasn't been deleted. " +
        "Deleting it while a subscription is live would keep charging them.",
      503,
    );
  }

  const base = { actor: actorId, subject: profileId, reason };
  if (!(await record(serviceClient, { ...base, action: "account.delete.started" }))) return bad(NOT_RECORDED, 500);

  try {
    cancelled = await cancelWebSubscriptions(profileId, { v2Key, projectId });
  } catch (err) {
    console.error("[admin-actions] could not cancel web subscription:", (err as Error).message);
    await record(serviceClient, { ...base, action: "account.delete.failed", details: { stage: "cancel_subscription" } });
    return bad(
      "Couldn't cancel this account's subscription, so it hasn't been deleted. Try again, or " +
        "cancel the subscription first.",
      503,
    );
  }

  // Step 1: scrub.
  //
  // `p_actor` is required here, and is the thing that was missing when this never worked. The RPC
  // gates on is_support_admin(), which reads auth.uid() — null under the service client — so every
  // deletion raised 42501 before touching anything. It now accepts the service role as
  // pre-authorised (this function already verified the caller with the caller's OWN client, above)
  // on condition that it says who it is acting for, because an audit row attributed to "the service
  // role" names nobody.
  const { error: scrubError } = await serviceClient.rpc("admin_scrub_account", {
    p_profile_id: profileId,
    p_reason: reason,
    p_actor: actorId,
  });
  if (scrubError) {
    console.error("[admin-actions] admin_scrub_account failed:", scrubError.message);
    await record(serviceClient, {
      ...base,
      action: "account.delete.failed",
      details: { stage: "scrub", cancelled_subscriptions: cancelled },
    });
    return bad("Couldn't delete this account's data. Please try again.", 500);
  }

  // Step 2: soft-delete the auth row. `shouldSoftDelete: true` sets deleted_at and leaves the row
  // in place — a hard delete cascades through profiles and would take the OTHER partner's shared
  // history with it.
  const { error: authError } = await serviceClient.auth.admin.deleteUser(profileId, true);
  if (authError) {
    console.error("[admin-actions] deleteUser failed:", authError.message);
    await record(serviceClient, {
      ...base,
      action: "account.delete.failed",
      details: { stage: "disable_sign_in", cancelled_subscriptions: cancelled },
    });
    // Step 1 already happened. Re-running is safe — both steps are idempotent — so this says so
    // rather than implying nothing was done.
    return bad(
      "Their data was deleted but disabling sign-in failed. Run this again — it's safe to repeat.",
      500,
    );
  }

  await record(serviceClient, { ...base, action: "account.delete", details: { cancelled_subscriptions: cancelled } });

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

  const v2Key = Deno.env.get("REVENUECAT_V2_API_KEY");
  const projectId = Deno.env.get("REVENUECAT_PROJECT_ID");
  if (!v2Key || !projectId) return bad("Billing provider is not configured.", 503);

  const base = { actor: actorId, subject: profileId, reason };
  if (!(await record(serviceClient, { ...base, action: "subscription.cancel.started" }))) return bad(NOT_RECORDED, 500);

  let cancelled = 0;
  try {
    cancelled = await cancelWebSubscriptions(profileId, { v2Key, projectId });
  } catch (err) {
    console.error("[admin-actions] could not cancel subscription:", (err as Error).message);
    await record(serviceClient, { ...base, action: "subscription.cancel.failed" });
    return bad("Couldn't cancel that subscription. Nothing has changed.", 503);
  }

  // Zero means there was nothing of ours to cancel — an App Store subscription, which Apple gives
  // no way to end for somebody else. Reported plainly rather than as success, so nobody tells a
  // customer a charge has stopped when it has not.
  await record(serviceClient, {
    ...base,
    action: cancelled > 0 ? "subscription.cancel" : "subscription.cancel.nothing_to_do",
    details: { cancelled },
  });

  return Response.json({ ok: true, cancelled });
}

/* To invoke locally:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/admin-actions' \
    --header 'Authorization: Bearer <support admin access token, with a code entered in the last 5 minutes>' \
    --header 'Content-Type: application/json' \
    --data '{"action":"subscription.cancel","profileId":"<uuid>","reason":"they emailed asking"}'

*/
