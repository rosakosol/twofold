// Notifies about a partner-connection request — either "someone wants to connect" (to the
// inviter, right after redeem_invite_code creates a pending request) or "your request was
// accepted" (to the requester, right after respond_to_connection_request accepts one). Called
// directly by the client right after each of those, same pattern as notify-couple-event —
// except neither event has a couple yet (that's the whole point pre-acceptance), so this looks
// up device_push_tokens by an explicit target profile id instead of resolving one via `couples`.
//
// Requires an `Authorization: Bearer <user access token>` header (the caller's Supabase auth
// session) — the caller is the *actor* whose action is being announced, not the recipient.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendAPNs } from "../_shared/apns.ts";

type EventType = "connection_requested" | "connection_accepted";

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

  if (input?.eventType !== "connection_requested" && input?.eventType !== "connection_accepted") {
    return Response.json({ error: "'eventType' must be 'connection_requested' or 'connection_accepted'" }, { status: 400 });
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

  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Confirm a real connection_requests row actually links the caller and the target in the
  // direction this eventType implies, before pushing anything — without this, any authenticated
  // user could push an arbitrary "wants to connect"/"accepted your request" notification, with
  // their own real name attached, to any other profile by UUID.
  const expectedMatch = input.eventType === "connection_requested"
    ? { inviter_id: input.targetProfileId, requester_id: user.id, status: "pending" }
    : { inviter_id: user.id, requester_id: input.targetProfileId, status: "accepted" };
  const { data: linkingRequest } = await serviceClient
    .from("connection_requests")
    .select("id")
    .match(expectedMatch)
    .maybeSingle();
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
      : { title: "You're connected! 🎉", body: `${actorName} accepted your connection request.` };

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
