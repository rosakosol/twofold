// Notifies about a partner-connection request — "someone wants to connect" (to the inviter,
// right after redeem_invite_code creates a pending request), "your request was accepted" (to the
// requester, right after respond_to_connection_request accepts one), or "still waiting on you"
// (to the inviter, right after send_connection_request_reminder — the requester nudging a
// still-pending request). Called directly by the client right after each of those, same pattern
// as notify-couple-event — except neither event has a couple yet (that's the whole point
// pre-acceptance), so this looks up device_push_tokens by an explicit target profile id instead
// of resolving one via `couples`.
//
// Requires an `Authorization: Bearer <user access token>` header (the caller's Supabase auth
// session) — the caller is the *actor* whose action is being announced, not the recipient.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendAPNs } from "../_shared/apns.ts";
import { enforceRateLimit } from "../_shared/rate-limit.ts";

/// The throttle this endpoint was missing entirely.
///
/// `send_connection_request_reminder` enforces one reminder per request per six hours, and
/// 20260906000000's header says why: without it somebody could "fire a push on every app launch".
/// But the throttle lives in the RPC, and calling this edge function directly skips both the RPC
/// and the ledger it writes to — so the limit was reachable only by callers who chose to go the
/// polite way.
///
/// The membership check below is real, so a target is always somebody with a genuine pending
/// request. What was unbounded is how often they could be told about it, with body text drawn
/// from the sender's own `first_name`, which is self-set and unvalidated.
///
/// Per-caller rather than per-request, because it sits here rather than in the ledger. A sender
/// with several outstanding invites shares one budget, which is the right way round: the person
/// being protected is the recipient.
const RATE_LIMIT = { bucket: "notify-connection-request", limit: 10, window: "1 hour" };

type EventType = "connection_requested" | "connection_accepted" | "connection_reminder";

interface Input {
  eventType: EventType;
  /// Who should receive the push — the inviter for connection_requested, the original
  /// requester for connection_accepted. Never derived from a couple (there isn't one yet for
  /// connection_requested, and the client already knows exactly who to notify in both cases).
  targetProfileId: string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  let input: Input;
  try {
    input = await req.json();
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (
    input?.eventType !== "connection_requested" &&
    input?.eventType !== "connection_accepted" &&
    input?.eventType !== "connection_reminder"
  ) {
    return Response.json(
      { error: "'eventType' must be 'connection_requested', 'connection_accepted', or 'connection_reminder'" },
      { status: 400 },
    );
  }
  if (!input.targetProfileId) {
    return Response.json({ error: "'targetProfileId' is required" }, { status: 400 });
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

  const limited = await enforceRateLimit(userClient, RATE_LIMIT);
  if (limited) return limited;

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Confirm a real connection_requests row actually links the caller and the target in the
  // direction this eventType implies, before pushing anything — without this, any authenticated
  // user could push an arbitrary "wants to connect"/"accepted your request" notification, with
  // their own real name attached, to any other profile by UUID.
  // `connection_accepted` happens in both directions, and only one of them worked.
  //
  // The obvious one: the inviter taps accept and tells the requester. The other is the auto-accept
  // path that 20261008000000 introduced — a tapped invite link connects the two outright, and the
  // *redeemer* is the one who calls this, about the inviter. That is the requester notifying the
  // inviter, the mirror image of the shape this used to match, so every one of those calls found
  // no row, answered 403, and was discarded by the client's `try?`. The inviter learned they had
  // been paired only when they next opened the app.
  //
  // Which matters because that migration's own justification rests on it: "The inviter is told.
  // `connection_accepted` already notifies, and this path fires it too." It fired and the server
  // refused it.
  //
  // Both orientations are accepted now, and the security property is unchanged: either way there
  // has to be a real `accepted` row linking the caller and the target, so this still cannot push
  // at an arbitrary uuid.
  let linkingRequest: { id: string } | null = null;
  let callerAccepted = false;

  if (input.eventType === "connection_accepted") {
    const { data: asInviter } = await serviceClient
      .from("connection_requests")
      .select("id")
      .match({ inviter_id: user.id, requester_id: input.targetProfileId, status: "accepted" })
      .maybeSingle();
    if (asInviter) {
      linkingRequest = asInviter;
      callerAccepted = true;
    } else {
      const { data: asRequester } = await serviceClient
        .from("connection_requests")
        .select("id")
        .match({ inviter_id: input.targetProfileId, requester_id: user.id, status: "accepted" })
        .maybeSingle();
      linkingRequest = asRequester;
    }
  } else {
    // connection_requested and connection_reminder are both the requester pinging the inviter
    // about the same still-open request, so they share one shape.
    const { data } = await serviceClient
      .from("connection_requests")
      .select("id")
      .match({ inviter_id: input.targetProfileId, requester_id: user.id, status: "pending" })
      .maybeSingle();
    linkingRequest = data;
  }

  if (!linkingRequest) {
    return Response.json({ error: "No matching connection request" }, { status: 403 });
  }

  // Best-effort from here on — a failure to notify should never surface as an error to the
  // client for what's fundamentally a side effect of an already-successful action.
  try {
    const { data: actorProfile } = await serviceClient
      .from("profiles")
      .select("first_name")
      .eq("id", user.id)
      .maybeSingle();
    const actorName = actorProfile?.first_name || "Someone";

    const { title, body } = input.eventType === "connection_requested"
      ? { title: "New connection request", body: `${actorName} wants to connect with you on Twofold.` }
      : input.eventType === "connection_reminder"
      ? { title: "Still waiting on you", body: `${actorName} is waiting for you to accept their connection request.` }
      : callerAccepted
      // The inviter accepted, and the requester is being told.
      ? { title: "You're connected! 🎉", body: `${actorName} accepted your connection request.` }
      // The redeemer followed a link, and the inviter is being told. The other wording would have
      // been addressed to somebody who never made a request — which is the second reason this
      // direction needed its own branch rather than just a wider match.
      : { title: "You're connected! 🎉", body: `${actorName} joined using your invite.` };

    const { data: tokens } = await serviceClient
      .from("device_push_tokens")
      .select("apns_token, environment")
      .eq("profile_id", input.targetProfileId);
    if (!tokens || tokens.length === 0) return Response.json({ ok: true });

    for (const token of tokens) {
      await sendAPNs(token.apns_token, token.environment, title, body, { eventType: input.eventType });
    }
  } catch (err) {
    console.error("[notify-connection-request] failed:", (err as Error).message);
  }

  return Response.json({ ok: true });
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/notify-connection-request' \
    --header 'Authorization: Bearer <user access token>' \
    --header 'Content-Type: application/json' \
    --data '{"eventType":"connection_requested","targetProfileId":"<uuid>"}'

*/
