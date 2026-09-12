// The words in a couple-activity push.
//
// Split out of `notify-couple-event/index.ts` so it can be tested. That file calls `Deno.serve` at
// import time, so anything inside it can only be exercised by standing up a server and sending a
// request — and the thing most worth pinning here is not the plumbing but the sentences, two of
// which make claims that are only true under conditions this module cannot see.
//
// Run the tests with: deno test supabase/functions/_shared/couple-event-copy.test.ts

export type EventType =
  | "drawing_saved"
  | "trip_added"
  | "memory_added"
  | "game_started"
  | "game_results_ready"
  | "game_partner_finished"
  | "game_reminder"
  | "game_turn";

/// What a session was, for the two events whose copy depends on it. A sudoku is a race against a
/// clock and a daily question is the couple's streak; "see how you matched" is true of neither.
export interface GameContext {
  detail?: string;
  gameType?: string;
  /// True for the couple's Daily Question — an ordinary 1-round `deep_conversations` session under
  /// the hood (see `get_daily_question_session`), so nothing else in a push payload tells it apart
  /// from a deck of the same type. The client sends the flag because only the client knows.
  isDaily?: boolean;
}

export function buildMessage(eventType: EventType, actorName: string, game: GameContext = {}): { title: string; body: string } {
  const { detail, gameType, isDaily } = game;
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
      // Both sides are in. For the Daily Question that is the moment the streak actually moves —
      // `advance_game_session` gates the increment on both partners having answered — so this is
      // the one push that can honestly call it done.
      if (isDaily) {
        return {
          title: "Streak kept!",
          body: `${actorName} has completed today's streak. Check how your answers match up!`,
        };
      }
      if (gameType === "sudoku") {
        return {
          title: "Both solved!",
          body: detail
            ? `You and ${actorName} both finished ${detail} - see how your times compare.`
            : `You and ${actorName} both solved it - see how your times compare.`,
        };
      }
      return {
        title: "Results are ready!",
        body: detail
          ? `You and ${actorName} both finished "${detail}" - see how you matched.`
          : `You and ${actorName} both finished - see how you matched.`,
      };
    case "game_partner_finished":
      // Half done, and deliberately not phrased as if the streak were safe. It is not: the
      // increment needs both answers, so this recipient is the one person who can still lose it
      // today. Nor can they "see how you match up" yet — a partner's answer stays hidden until
      // their own is written.
      if (isDaily) {
        return {
          title: "Your turn!",
          body: `${actorName} has answered today's question. Answer yours to keep the streak going.`,
        };
      }
      if (gameType === "sudoku") {
        return {
          title: "Your turn!",
          body: detail
            ? `${actorName} finished ${detail} - your grid is waiting.`
            : `${actorName} solved their sudoku - your grid is waiting.`,
        };
      }
      return {
        title: "Your turn!",
        body: detail
          ? `${actorName} finished "${detail}" - it's your turn to play.`
          : `${actorName} finished their answers - it's your turn to play.`,
      };
    case "game_reminder":
      return { title: "Reminder", body: detail ? `${actorName} wants you to complete "${detail}".` : `${actorName} sent you a reminder to complete your game.` };
    case "game_turn":
      // Names the game, because these two are the only ones that can be waiting on you and a
      // couple may well have both going at once — "it's your turn" alone would not say where.
      return {
        title: "Your move",
        body: turnGameName(gameType)
          ? `${actorName} moved in ${turnGameName(gameType)} - it's your turn.`
          : `${actorName} moved - it's your turn.`,
      };
  }
}

/// The turn-based games, by name. Returns null for anything else: this event should only ever
/// carry `chess` or `connect_four`, and inventing a label for a third would be guessing.
function turnGameName(gameType?: string): string | null {
  switch (gameType) {
    case "chess": return "Chess";
    case "connect_four": return "Connect 4";
    default: return null;
  }
}

// Second-person copy for `target: "self"` — the recipient is the actor themselves, not their
// partner, so this deliberately doesn't reuse buildMessage's "{actorName} did X" phrasing.
export function buildSelfMessage(eventType: EventType, game: GameContext = {}): { title: string; body: string } {
  const { detail, gameType, isDaily } = game;
  switch (eventType) {
    case "drawing_saved":
      return { title: "Doodle saved", body: "Your new drawing was saved." };
    case "trip_added":
      return { title: "Trip saved", body: detail ? `Your trip "${detail}" was saved.` : "Your new trip was saved." };
    case "memory_added":
      return { title: "Memory saved", body: detail ? `Your memory "${detail}" was saved.` : "Your new memory was saved." };
    case "game_started":
      return { title: "Game started", body: detail ? `You started "${detail}".` : "You started a new game." };
    case "game_results_ready":
      // Kept in step with `buildMessage`'s branches above. This path is a test harness rather
      // than a real user journey, and a harness that reports the old copy for the one event
      // somebody is trying to check is worse than no harness.
      if (isDaily) {
        return { title: "Streak kept!", body: "You both completed today's streak. Check how your answers match up!" };
      }
      if (gameType === "sudoku") {
        return {
          title: "Both solved!",
          body: detail ? `You both finished ${detail} - see how your times compare.` : "You both solved it - see how your times compare.",
        };
      }
      return {
        title: "Results are ready!",
        body: detail ? `See how you and your partner matched on "${detail}".` : "See how you and your partner matched.",
      };
    case "game_partner_finished":
      if (isDaily) {
        return { title: "Your turn!", body: "Answer today's question to keep the streak going." };
      }
      if (gameType === "sudoku") {
        return {
          title: "Your turn!",
          body: detail ? `Your ${detail} grid is waiting.` : "Your sudoku grid is waiting.",
        };
      }
      return {
        title: "Your turn!",
        body: detail ? `It's your turn to play "${detail}".` : "It's your turn to play.",
      };
    case "game_reminder":
      return { title: "Reminder", body: detail ? `Complete "${detail}".` : "Complete your game." };
    case "game_turn":
      return { title: "Move played", body: "Your move was played." };
  }
}
