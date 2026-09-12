// Tells the opponent it is their move, for Chess and Connect 4.
//
// Why this is not `notify-couple-event`
// -------------------------------------
//
// That function works out who the actor is from the caller's JWT — `userClient.auth.getUser()`,
// 401 if there isn't one — and derives the recipient as "the other half of that user's couple".
// That is exactly right for something a person did in the app, and unusable here: this is invoked
// by a database trigger on `game_moves` (see 20261020000000), under the service role, with no end
// user on the connection at all. The chess half could not supply a user JWT even in principle —
// its move arrives through `play-chess-move`, running as the service role itself.
//
// The alternative was teaching `notify-couple-event` to accept an explicit actor and recipient
// when the caller holds the service key. That is a spoofing surface on the one function every
// couple event goes through, added for a single caller. A separate endpoint that only ever accepts
// the service role is the smaller thing to get right.
//
// Everything downstream is shared: the same `buildMessage` copy, the same preference row, the same
// `device_push_tokens` fan-out and the same `sendAPNs`.
//
// The cooldown is NOT here. It lives in the trigger, as an atomic upsert, so that two moves
// landing together cannot both decide they are allowed to send — a check in this function would be
// a race across two invocations.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendAPNs } from "../_shared/apns.ts";
import { buildMessage } from "../_shared/couple-event-copy.ts";

interface Input {
  actorId?: string;
  actorName?: string;
  recipientId?: string;
  sessionId?: string;
  gameType?: string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  // Service role only. Compared against the key itself rather than by decoding a role claim: this
  // endpoint takes the recipient as a parameter, so anything less than "you already hold the
  // service key" would let a caller push arbitrary copy to an arbitrary profile.
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const presented = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (presented !== serviceKey) {
    return Response.json({ error: "Not authorised" }, { status: 401 });
  }

  let input: Input;
  try {
    input = await req.json();
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { actorId, recipientId, sessionId, gameType } = input;
  if (!actorId || !recipientId || !sessionId) {
    return Response.json({ error: "actorId, recipientId and sessionId are required" }, { status: 400 });
  }
  if (gameType !== "chess" && gameType !== "connect_four") {
    return Response.json({ error: "gameType must be chess or connect_four" }, { status: 400 });
  }
  // A game cannot be waiting on the person who just moved. The trigger already refuses this, so
  // reaching it means one of the two is wrong and a push would be actively confusing.
  if (actorId === recipientId) {
    return Response.json({ error: "actorId and recipientId must differ" }, { status: 400 });
  }

  const db = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey);

  // Best-effort from here, like every other notify path: a push that fails to send must not turn
  // an already-committed move into an error.
  try {
    // Re-read the recipient's own preference rather than trusting the caller. No row means
    // "everything on", matching the table's column defaults and `notify-couple-event`.
    const { data: prefRow } = await db
      .from("notification_preferences")
      .select("partner_game_turn")
      .eq("profile_id", recipientId)
      .maybeSingle();
    if (prefRow && prefRow.partner_game_turn === false) {
      return Response.json({ ok: true, skipped: "preference" });
    }

    const { data: tokens } = await db
      .from("device_push_tokens")
      .select("apns_token, environment")
      .eq("profile_id", recipientId);
    if (!tokens || tokens.length === 0) {
      return Response.json({ ok: true, skipped: "no tokens" });
    }

    const actorName = input.actorName?.trim() || "Your partner";
    const { title, body } = buildMessage("game_turn", actorName, { gameType });

    // Top-level alongside `aps`, which is where the app reads deep-link keys out of `userInfo` —
    // this is what opens the board rather than the games list.
    const data = { sessionId, gameType };

    await Promise.all(
      tokens.map((token) =>
        sendAPNs(token.apns_token, token.environment, title, body, data).catch((error) => {
          console.error("[notify-game-turn] send failed", error);
        })
      ),
    );

    return Response.json({ ok: true, sent: tokens.length });
  } catch (error) {
    console.error("[notify-game-turn] failed", error);
    return Response.json({ ok: true, error: String(error) });
  }
});
