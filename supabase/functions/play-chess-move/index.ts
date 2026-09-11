// Plays one chess move, and decides for itself whether it was legal and whether it ended the game.
//
// ---------------------------------------------------------------------------
// Why this is an edge function and not an RPC
// ---------------------------------------------------------------------------
//
// Connect 4 validates in plpgsql, because replaying 42 discs and looking for four in a row is forty
// lines. Chess is not that: legal move generation is a library's worth of work, and plpgsql is the
// wrong language to write it in.
//
// That does not mean the client decides. Ending a game is a *write*, the move log is append-only,
// and a bug in one device's rules must not be able to end a game wrongly for both people — the same
// argument `play_connect_four_move` makes. Only the mechanism differs: Deno and `chess.js` rather
// than Postgres.
//
// `game_moves` grants no insert to `authenticated`, so this function — writing with the service
// role — is the only way a move can reach the table.
//
// ---------------------------------------------------------------------------
// Two rules engines
// ---------------------------------------------------------------------------
//
// The app runs ChessKit on the device and this runs chess.js. That duplication is deliberate for
// the same reason Connect 4's is: the board has to be drawn and legal destinations shown as a
// finger moves, which cannot wait for a round trip. What makes it survivable is which one decides.
// If the client's is wrong, a player is refused a move they thought was legal and the board is
// corrected. If this one were wrong, the game would end incorrectly and there would be no undoing
// it.
//
// ---------------------------------------------------------------------------
// The race
// ---------------------------------------------------------------------------
//
// Whose turn it is, checked below, produces a useful error. The unique index on
// (session_id, move_number) is what makes the outcome *correct* when two moves arrive together —
// exactly one survives, and the loser gets a conflict rather than a forked board. See
// 20261013000100_game_moves.sql.

import { createClient } from "jsr:@supabase/supabase-js@2";
// The replay and the endgame classification live next door so they can be tested without standing
// up this server — see `_shared/chess-rules.ts`.
import { describe, playerToMove, replay } from "../_shared/chess-rules.ts";

interface Input {
  sessionId?: string;
  /// Origin square, e.g. "e2".
  from?: string;
  /// Destination square, e.g. "e4".
  to?: string;
  /// Promotion piece for a pawn reaching the last rank: "q", "r", "b" or "n".
  /// Absent for every other move.
  promotion?: string;
}

const PROMOTION_PIECES = ["q", "r", "b", "n"];

function bad(error: string, status = 400) {
  return Response.json({ error }, { status });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return bad("Method not allowed", 405);

  let input: Input;
  try {
    input = await req.json();
  } catch {
    return bad("Invalid JSON body");
  }

  const { sessionId, from, to, promotion } = input;
  if (!sessionId || !from || !to) return bad("sessionId, from and to are required");
  if (promotion && !PROMOTION_PIECES.includes(promotion)) return bad("Invalid promotion piece");

  // The caller's own token, so `auth.getUser()` says who is moving. Everything after that reads
  // with the service role — the caller cannot see `game_moves` rows for a session they are not in,
  // and this function needs the whole log to replay it.
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return bad("Not authenticated", 401);

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: session } = await db
    .from("game_sessions")
    .select("id, game_type, couple_id, initiator_id, status")
    .eq("id", sessionId)
    .maybeSingle();

  if (!session || session.game_type !== "chess") return bad("No such game", 404);

  const { data: couple } = await db
    .from("couples")
    .select("partner_a_id, partner_b_id")
    .eq("id", session.couple_id)
    .maybeSingle();
  if (!couple) return bad("No such game", 404);

  const players = [couple.partner_a_id, couple.partner_b_id];
  if (!players.includes(user.id)) return bad("Not your game", 403);

  // Any status that is not a live game. A move landing on an abandoned or expired board would
  // reopen it for one player and not the other — the same hole Connect 4 had.
  if (!["active", "waiting_for_partner"].includes(session.status)) {
    return bad("chess_finished");
  }

  const { data: moves, error: movesError } = await db
    .from("game_moves")
    .select("move_number, move")
    .eq("session_id", sessionId)
    .order("move_number");
  if (movesError) return bad(movesError.message, 500);

  // The position, rebuilt from the log. Never from a stored FEN: a board is only as trustworthy as
  // the moves that made it, and a cached position is a second copy of the game that can disagree
  // with the log it came from.
  const chess = replay((moves ?? []).map((row) => row.move));
  if (!chess) {
    // A log this build cannot replay is a game that cannot be continued, and guessing at it would
    // be worse than stopping.
    console.error(`[play-chess-move] session ${sessionId} has a log that cannot be replayed`);
    return bad("This game can't be continued.", 500);
  }

  const other = players.find((id) => id !== session.initiator_id)!;
  if (playerToMove(chess, session.initiator_id, other) !== user.id) {
    return bad("chess_not_your_turn");
  }

  let played;
  try {
    played = chess.move({ from, to, promotion: promotion as never });
  } catch {
    // chess.js throws on an illegal move rather than returning null. Either way this is the
    // ordinary case of somebody dragging a piece somewhere it may not go, so it is a named outcome
    // rather than an error.
    return bad("chess_illegal_move");
  }
  if (!played) return bad("chess_illegal_move");

  const moveNumber = (moves ?? []).length;
  const { error: insertError } = await db.from("game_moves").insert({
    session_id: sessionId,
    move_number: moveNumber,
    player_id: user.id,
    // Stored in the notation chess.js will read back. LAN rather than SAN, because SAN depends on
    // the position it was written in ("Nf3" is meaningless without the board) and a log that can
    // only be read in order is a log that cannot be checked out of order.
    move: `${played.from}${played.to}${played.promotion ?? ""}`,
  });

  if (insertError) {
    // A unique violation here is the race, not a failure: somebody else's move took this number
    // first. Their board is the real one, and this caller re-reads rather than retries.
    if (insertError.code === "23505") return bad("chess_not_your_turn");
    return bad(insertError.message, 500);
  }

  // Worked out here rather than taken from the client, which is the whole point of this function.
  const state = describe(chess);

  if (state.finished) {
    await db
      .from("game_sessions")
      .update({ status: "completed", completed_at: new Date().toISOString(), updated_at: new Date().toISOString() })
      .eq("id", sessionId);
  }

  return Response.json({
    move_number: moveNumber,
    finished: state.finished,
    // Only a checkmate has a winner. Every other ending is a draw, and naming a winner for one of
    // those would be the server inventing a result.
    winner_id: state.hasWinner ? user.id : null,
    outcome: state.outcome,
    in_check: state.inCheck,
  });
});

/* To invoke locally:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/play-chess-move' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --header 'Authorization: Bearer <user-access-token>' \
    --data '{"sessionId":"<uuid>","from":"e2","to":"e4"}'

*/
