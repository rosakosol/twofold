import type { GameType } from "@/lib/games/contentTypes";

/** Each game's gradient (docs/TWOFOLD_WEBSITE.md, section 2.2), for its colour chip and deck header. */
export function gameGradient(gameType: GameType | null | undefined): string {
  switch (gameType) {
    case "deep_conversations":
      return "var(--grad-deep)";
    case "this_or_that":
      return "var(--grad-this)";
    case "trivia_battle":
      return "var(--grad-trivia)";
    case "more_likely":
      return "var(--grad-likely)";
    default:
      return "var(--grad-daily)";
  }
}

/** A small square in the game's gradient: which game a row belongs to, at a glance. */
export function GameChip({ gameType }: { gameType: GameType | null | undefined }) {
  return <span className="game-chip" style={{ background: gameGradient(gameType) }} aria-hidden />;
}
