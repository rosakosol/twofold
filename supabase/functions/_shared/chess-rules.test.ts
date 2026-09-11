// Tests for the one thing this server decides about chess: whether a game is over, and how.
//
// Getting it wrong is not correctable. The move log is append-only and the session is marked
// completed, so a game called checkmate when it was stalemate has recorded a winner where there was
// a draw — for both people, permanently. That is why this is on the server at all, and it is the
// only part worth testing here: chess.js knows the rules, and what is being pinned is that this
// code asks it the right questions in the right order.
//
// Run with: deno test supabase/functions/_shared/chess-rules.test.ts

import { assertEquals } from "jsr:@std/assert";
import { describe, playerToMove, replay } from "./chess-rules.ts";

Deno.test("a fresh game is not over and it is white's move", () => {
  const chess = replay([])!;
  const state = describe(chess);
  assertEquals(state.finished, false);
  assertEquals(state.outcome, null);
  assertEquals(state.turn, "w");
});

Deno.test("a log replays into the position it describes", () => {
  const chess = replay(["e2e4", "e7e5", "g1f3"])!;
  assertEquals(chess.turn(), "b");
  assertEquals(chess.history().length, 3);
});

Deno.test("a log with an illegal move is refused rather than partially replayed", () => {
  // A game that cannot be continued is better stopped than guessed at — a partially replayed board
  // is a position neither player has ever seen.
  assertEquals(replay(["e2e4", "e2e4"]), null);
  assertEquals(replay(["totally-not-a-move"]), null);
});

Deno.test("fool's mate is a checkmate, with a winner", () => {
  // 1. f3 e5 2. g4 Qh4#
  const chess = replay(["f2f3", "e7e5", "g2g4", "d8h4"])!;
  const state = describe(chess);
  assertEquals(state.finished, true);
  assertEquals(state.outcome, "checkmate");
  assertEquals(state.hasWinner, true);
  assertEquals(state.inCheck, true);
});

Deno.test("stalemate is a draw and is not reported as checkmate", () => {
  // The distinction the whole file exists for: one legal move apart, a win against a draw.
  const chess = replay([])!;
  chess.load("7k/5K2/8/8/6Q1/8/8/8 w - - 0 1");
  chess.move({ from: "g4", to: "g6" });

  const state = describe(chess);
  assertEquals(state.finished, true);
  assertEquals(state.outcome, "stalemate");
  assertEquals(state.hasWinner, false, "a stalemate has no winner");
  assertEquals(state.inCheck, false, "stalemate is precisely not check");
});

Deno.test("insufficient material is named as itself, not as the fifty-move rule", () => {
  // `isDraw()` is true for every drawn ending, so asking it before the specific reasons would
  // report all of them as fifty moves. This is what pins the order.
  const chess = replay([])!;
  chess.load("7k/8/8/8/8/8/8/K7 w - - 0 1");

  const state = describe(chess);
  assertEquals(state.finished, true);
  assertEquals(state.outcome, "insufficient_material");
  assertEquals(state.hasWinner, false);
});

Deno.test("threefold repetition is named as itself", () => {
  // Knights out and back, twice, returning to the start position for the third time.
  const chess = replay([
    "g1f3", "g8f6", "f3g1", "f6g8",
    "g1f3", "g8f6", "f3g1", "f6g8",
  ])!;
  const state = describe(chess);
  assertEquals(state.outcome, "repetition");
  assertEquals(state.hasWinner, false);
});

Deno.test("a game in progress reports check without ending", () => {
  // Bare kings and a white queen: Qh5-e5 checks down the e-file, and the black king simply steps
  // to d7. Built from a position rather than an opening because the obvious opening line for this
  // — 1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7 — is scholar's mate, which is the opposite of the
  // case being tested.
  const chess = replay([])!;
  chess.load("4k3/8/8/7Q/8/8/8/4K3 w - - 0 1");
  chess.move({ from: "h5", to: "e5" });

  const state = describe(chess);
  assertEquals(state.inCheck, true);
  assertEquals(state.finished, false, "the king can still step aside");
  assertEquals(state.outcome, null);
});

Deno.test("the initiator plays white", () => {
  const initiator = "aaaa", partner = "bbbb";
  assertEquals(playerToMove(replay([])!, initiator, partner), initiator);
  assertEquals(playerToMove(replay(["e2e4"])!, initiator, partner), partner);
  assertEquals(playerToMove(replay(["e2e4", "e7e5"])!, initiator, partner), initiator);
});

Deno.test("promotion round trips through the log's notation", () => {
  // The log stores LAN with the promotion piece appended ("a7a8q"). Losing that letter would
  // promote to a queen by default and quietly change somebody's game.
  const chess = replay([])!;
  chess.load("8/P6k/8/8/8/8/8/K7 w - - 0 1");
  const move = chess.move({ from: "a7", to: "a8", promotion: "n" });
  assertEquals(move.promotion, "n");

  const notation = `${move.from}${move.to}${move.promotion ?? ""}`;
  assertEquals(notation, "a7a8n");

  // And it replays back to the same thing.
  const replayed = replay([])!;
  replayed.load("8/P6k/8/8/8/8/8/K7 w - - 0 1");
  replayed.move(notation);
  assertEquals(replayed.get("a8")?.type, "n");
});
