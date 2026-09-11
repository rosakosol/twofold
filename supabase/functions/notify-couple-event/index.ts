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
// The sentences themselves live next door so they can be tested without standing up this server.
import { buildMessage, buildSelfMessage, type EventType } from "../_shared/couple-event-copy.ts";

interface Input {
  eventType: EventType;
  detail?: string;
  /// Present for game_reminder/game_results_ready — lets a tap on the delivered notification
  /// deep-link straight into that session instead of just opening the app.
  sessionId?: string;
  gameType?: string;
  /// True for the couple's Daily Question. Only changes the wording, and only for
  /// game_results_ready/game_partner_finished — that session is the one whose completion moves
  /// the streak, and "a game" is the wrong word for the thing somebody is about to lose.
  ///
  /// Sent by the client rather than worked out here: a daily session is an ordinary 1-round
  /// `deep_conversations` session (see `get_daily_question_session`), so nothing else in this
  /// payload tells it apart from a deck of the same type.
  isDaily?: boolean;
  /// "partner" (default) notifies the caller's partner about the caller's activity, same as
  /// always. "self" notifies the caller's *own* devices instead — added as a deliberately
  /// controllable way to exercise the real end-to-end push pipeline (device registration →
  /// APNs → delivery) from an ordinary in-app action, without touching the partner's device at
  /// all. No preference-column gate applies to "self" — those columns govern whether *the
  /// partner* wants to hear about the caller's activity, which doesn't apply when the caller is
  /// the recipient.
  target?: "self" | "partner";
}

const VALID_EVENT_TYPES: EventType[] = [
  "drawing_saved",
  "trip_added",
  "memory_added",
  "game_started",
  "game_results_ready",
  "game_partner_finished",
  "game_reminder",
];

// Event type -> notification_preferences column, mirroring the pattern in _shared/notify.ts.
// game_reminder is deliberately absent — it's an explicit, one-off nudge the sender chooses to
// send, not ambient activity, so it's never muted.
// Spelled out as a union rather than `string`, so a typo is a compile error instead of a silent
// behaviour change: an unrecognised column name finds no row, "no row" means "notify", and the
// result is a notification the recipient has switched off and cannot switch off again.
type PreferenceColumn =
  | "partner_drawing_saved"
  | "partner_trip_added"
  | "partner_memory_added"
  | "partner_game_started"
  | "partner_game_results_ready"
  | "partner_game_partner_finished";

const PREFERENCE_COLUMN: Partial<Record<EventType, PreferenceColumn>> = {
  drawing_saved: "partner_drawing_saved",
  trip_added: "partner_trip_added",
  memory_added: "partner_memory_added",
  game_started: "partner_game_started",
  game_results_ready: "partner_game_results_ready",
  game_partner_finished: "partner_game_partner_finished",
};

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
    if (input.target === "self") {
      const { data: tokens } = await serviceClient
        .from("device_push_tokens")
        .select("apns_token, environment")
        .eq("profile_id", user.id);
      if (!tokens || tokens.length === 0) return Response.json({ ok: true });

      const { title, body } = buildSelfMessage(input.eventType, {
        detail: input.detail,
        gameType: input.gameType,
        isDaily: input.isDaily,
      });
      const data = input.sessionId
        ? { sessionId: input.sessionId, gameType: input.gameType, eventType: input.eventType }
        : input.eventType === "drawing_saved"
        ? { route: "drawing_pad", eventType: input.eventType }
        : undefined;
      for (const token of tokens) {
        await sendAPNs(token.apns_token, token.environment, title, body, data);
      }
      return Response.json({ ok: true });
    }

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
      // Selects the whole row rather than the one column, because the column is only known at
      // runtime. PostgREST's types resolve a select against the literal string passed to it, so a
      // variable column name gave back an error type instead of a row — and the cast that followed
      // was casting *from that error type*, which is why this file has never type-checked. Reading
      // the row properly makes the cast an honest one, and costs nothing: this is a single row of
      // booleans, fetched one at a time either way.
      const { data: prefRow } = await serviceClient
        .from("notification_preferences")
        .select("*")
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

    const { title, body } = buildMessage(input.eventType, actorName, {
      detail: input.detail,
      gameType: input.gameType,
      isDaily: input.isDaily,
    });
    const data = input.sessionId
      ? { sessionId: input.sessionId, gameType: input.gameType, eventType: input.eventType }
      : input.eventType === "drawing_saved"
      // Not the same destination as the self-notification above, though the event type is
      // identical. That one says "your new drawing was saved" and belongs in your own editor;
      // this one says "<partner> saved a new drawing", and tapping it to be shown your own
      // canvas instead of the drawing you were just told about is the whole reason it exists.
      ? { route: "partner_drawing_pad", eventType: input.eventType }
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
