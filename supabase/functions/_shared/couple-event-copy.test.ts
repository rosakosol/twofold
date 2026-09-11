// Tests for the words in a couple-activity push.
//
// Copy is usually not worth pinning. These two claims are, because both are false under
// conditions this module cannot see, and getting either wrong is only visible on somebody's lock
// screen:
//
//   1. "Check how your answers match up" needs both answers to exist. A partner's answer is
//      hidden by RLS until you have written your own, so on the half-done event that sentence
//      sends someone to a screen that cannot show them what they were promised.
//
//   2. "Streak kept" needs both answers too. `advance_game_session` gates the daily increment on
//      both partners having answered (see 20260907000000_fix_streak_both_complete_and_lapse.sql,
//      which restored that gate after two migrations dropped it) — so telling the one person who
//      can still lose today's streak that it is safe is precisely backwards.
//
// Run with: deno test supabase/functions/_shared/couple-event-copy.test.ts

import { assertEquals, assertStringIncludes } from "jsr:@std/assert";
import { buildMessage, buildSelfMessage } from "./couple-event-copy.ts";

Deno.test("the daily question's results push names the streak and invites the comparison", () => {
  const { title, body } = buildMessage("game_results_ready", "Erin", { isDaily: true });
  assertEquals(title, "Streak kept!");
  assertEquals(body, "Erin has completed today's streak. Check how your answers match up!");
});

Deno.test("the daily question's your-turn push does not claim the streak is safe", () => {
  const { body } = buildMessage("game_partner_finished", "Erin", { isDaily: true });
  assertStringIncludes(body, "Erin has answered today's question");
  assertStringIncludes(body, "keep the streak going");
  // The two promises that only the both-answered push can make.
  assertEquals(body.includes("match up"), false);
  assertEquals(body.includes("Streak kept"), false);
});

Deno.test("a daily question is never described as a deck", () => {
  // `detail` carries the deck title for an ordinary session. A daily session is a
  // `deep_conversations` session under the hood, so it can arrive carrying one — and the streak
  // copy must win over it rather than fall back to 'both finished "..."'.
  for (const event of ["game_results_ready", "game_partner_finished"] as const) {
    const { body } = buildMessage(event, "Erin", { detail: "Getting to Know You", isDaily: true });
    assertEquals(body.includes("Getting to Know You"), false);
  }
});

Deno.test("sudoku is compared on time, not on matching", () => {
  const both = buildMessage("game_results_ready", "Erin", { gameType: "sudoku", detail: "Hard Sudoku" });
  assertEquals(both.title, "Both solved!");
  assertEquals(both.body, "You and Erin both finished Hard Sudoku - see how your times compare.");
  // "See how you matched" is the match-game sentence, and there is nothing to match in a sudoku:
  // both players fill in the same one grid.
  assertEquals(both.body.includes("matched"), false);

  const half = buildMessage("game_partner_finished", "Erin", { gameType: "sudoku", detail: "Hard Sudoku" });
  assertEquals(half.title, "Your turn!");
  assertEquals(half.body, "Erin finished Hard Sudoku - your grid is waiting.");
});

Deno.test("a sudoku with no difficulty resolved still reads as a sentence", () => {
  // `SudokuGameStore.notifyPartnerOfSolve` sends no detail if the puzzle has not been generated.
  // Every branch has to survive that rather than rendering an empty pair of quotes.
  const both = buildMessage("game_results_ready", "Erin", { gameType: "sudoku" });
  const half = buildMessage("game_partner_finished", "Erin", { gameType: "sudoku" });
  assertEquals(both.body, "You and Erin both solved it - see how your times compare.");
  assertEquals(half.body, "Erin solved their sudoku - your grid is waiting.");
});

Deno.test("an ordinary deck keeps the copy it already had", () => {
  // The branches above are additions, not a rewrite. Every session that is neither daily nor a
  // sudoku must be untouched.
  const both = buildMessage("game_results_ready", "Erin", { detail: "Getting to Know You" });
  assertEquals(both.title, "Results are ready!");
  assertEquals(both.body, 'You and Erin both finished "Getting to Know You" - see how you matched.');

  const half = buildMessage("game_partner_finished", "Erin", { detail: "Getting to Know You" });
  assertEquals(half.title, "Your turn!");
  assertEquals(half.body, 'Erin finished "Getting to Know You" - it\'s your turn to play.');

  assertEquals(buildMessage("trip_added", "Erin", { detail: "Tokyo" }).title, "New trip");
  assertEquals(buildMessage("drawing_saved", "Erin").title, "New doodle");
});

Deno.test("the self-target harness reports the same branch as the real push", () => {
  // Its whole purpose is checking what a push will look like without involving a partner. A
  // harness still reporting the generic copy for the event being tested is a trap, not a tool.
  assertEquals(buildSelfMessage("game_results_ready", { isDaily: true }).title, "Streak kept!");
  assertEquals(buildSelfMessage("game_results_ready", { gameType: "sudoku" }).title, "Both solved!");
  assertStringIncludes(
    buildSelfMessage("game_partner_finished", { isDaily: true }).body,
    "keep the streak going",
  );
  assertEquals(
    buildSelfMessage("game_results_ready", { detail: "Getting to Know You" }).title,
    "Results are ready!",
  );
});
