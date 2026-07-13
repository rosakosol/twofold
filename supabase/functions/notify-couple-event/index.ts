// Notifies the caller's partner about a couple-activity event they just triggered — saving a
// drawing pad doodle, adding a trip, adding a memory, or starting a game. Called directly by the
// client right after each of those (all client-side direct-insert writes with no edge function
// of their own, unlike flights), rather than via a DB trigger — keeps this consistent with how
// those features already work, no new pg_net/trigger plumbing needed.
//
// Requires an `Authorization: Bearer <user access token>` header (the caller's Supabase auth
// session) — the caller is the *actor* whose activity is being announced, not the recipient.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendAPNs } from "../_shared/apns.ts";

type EventType = "drawing_saved" | "trip_added" | "memory_added" | "game_started" | "game_results_ready" | "game_reminder";

interface Input {
  eventType: EventType;
  detail?: string;
  /// Present for game_reminder/game_results_ready — lets a tap on the delivered notification
  /// deep-link straight into that session instead of just opening the app.
  sessionId?: string;
  gameType?: string;
}

const VALID_EVENT_TYPES: EventType[] = [
  "drawing_saved",
  "trip_added",
  "memory_added",
  "game_started",
  "game_results_ready",
  "game_reminder",
];

// Event type -> notification_preferences column, mirroring the pattern in _shared/notify.ts.
// game_reminder is deliberately absent — it's an explicit, one-off nudge the sender chooses to
// send, not ambient activity, so it's never muted.
const PREFERENCE_COLUMN: Partial<Record<EventType, string>> = {
  drawing_saved: "partner_drawing_saved",
  trip_added: "partner_trip_added",
  memory_added: "partner_memory_added",
  game_started: "partner_game_started",
  game_results_ready: "partner_game_results_ready",
};

function buildMessage(eventType: EventType, actorName: string, detail?: string): { title: string; body: string } {
  switch (eventType) {
    case "drawing_saved":
      return { title: "New doodle", body: `${actorName} saved a new drawing` };
    case "trip_added":
      return { title: "New trip", body: detail ? `${actorName} added a trip: ${detail}.` : `${actorName} added a new trip.` };
    case "memory_added":
      return { title: "New memory", body: detail ? `${actorName} added a memory: ${detail}.` : `${actorName} added a new memory.` };
    case "game_started":
      return { title: "Game time", body: detail ? `${actorName} started a game: ${detail}.` : `${actorName} started a game.` };
    case "game_results_ready":
      return { title: "Results are ready!", body: `You and ${actorName} both finished - see how you matched.` };
    case "game_reminder":
      return { title: "Reminder", body: detail ? `${actorName} wants you to to complete "${detail}".` : `${actorName} sent you a reminder to complete your game.` };
  }
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

  if (!input?.eventType || !VALID_EVENT_TYPES.includes(input.eventType)) {
    return Response.json({ error: "'eventType' must be one of " + VALID_EVENT_TYPES.join(", ") }, { status: 400 });
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

  // Best-effort from here on — a failure to notify should never surface as an error to the
  // client for what's fundamentally a side effect of an already-successful action.
  try {
    const { data: couple } = await serviceClient
      .from("couples")
      .select("partner_a_id, partner_b_id")
      .or(`partner_a_id.eq.${user.id},partner_b_id.eq.${user.id}`)
      .eq("status", "active")
      .maybeSingle();
    if (!couple) return Response.json({ ok: true });

    const partnerId = couple.partner_a_id === user.id ? couple.partner_b_id : couple.partner_a_id;
    if (!partnerId) return Response.json({ ok: true });

    const { data: actorProfile } = await serviceClient
      .from("profiles")
      .select("first_name")
      .eq("id", user.id)
      .maybeSingle();
    const actorName = actorProfile?.first_name || "Your partner";

    const prefColumn = PREFERENCE_COLUMN[input.eventType];
    if (prefColumn) {
      const { data: prefRow } = await serviceClient
        .from("notification_preferences")
        .select(prefColumn)
        .eq("profile_id", partnerId)
        .maybeSingle();
      // No row yet defaults to "notify" (matches the table's own column defaults).
      const allowed = prefRow ? Boolean((prefRow as Record<string, unknown>)[prefColumn]) : true;
      if (!allowed) return Response.json({ ok: true });
    }

    const { data: tokens } = await serviceClient
      .from("device_push_tokens")
      .select("apns_token, environment")
      .eq("profile_id", partnerId);
    if (!tokens || tokens.length === 0) return Response.json({ ok: true });

    const { title, body } = buildMessage(input.eventType, actorName, input.detail);
    const data = input.sessionId
      ? { sessionId: input.sessionId, gameType: input.gameType, eventType: input.eventType }
      : undefined;
    for (const token of tokens) {
      await sendAPNs(token.apns_token, token.environment, title, body, data);
    }
  } catch (err) {
    console.error("[notify-couple-event] failed:", (err as Error).message);
  }

  return Response.json({ ok: true });
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/notify-couple-event' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --header 'Authorization: Bearer <user-access-token>' \
    --data '{"eventType":"trip_added","detail":"Melbourne to Tokyo"}'

*/
