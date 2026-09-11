// Replaying a chess move log, and saying what the position is.
//
// Split out of `play-chess-move/index.ts` so it can be tested: that file calls `Deno.serve` at
// import time, so nothing in it can be reached without standing up a server — and the part worth
// testing is not the plumbing but the answer to "is this game over, and how".
//
// That answer is the reason the whole function exists. Ending a game is a write against an
// append-only log, so getting it wrong is not correctable: a game called checkmate when it was
// stalemate has recorded a winner where there was a draw, for both people, permanently.
//
// Run the tests with: deno test supabase/functions/_shared/chess-rules.test.ts

import { Chess } from "npm:chess.js@1.4.0";

/// How a game ended. Null while it is still being played.
///
/// Every one of these except `checkmate` is a draw. They are kept apart rather than collapsed into
/// "draw" because they are different things to be told — "you repeated the position three times"
/// and "neither of you has enough material to mate" are different games — and because collapsing
/// them is a decision the screen can make later, while un-collapsing them is not.
export type ChessOutcome =
  | "checkmate"
  | "stalemate"
  | "insufficient_material"
  | "repetition"
  | "fifty_moves";

export interface ChessPositionState {
  finished: boolean;
  outcome: ChessOutcome | null;
  /// True only for checkmate. Every other ending has no winner, and naming one would be the server
  /// inventing a result.
  hasWinner: boolean;
  inCheck: boolean;
  /// "w" or "b" — whose turn it is *now*, after whatever move was just played.
  turn: string;
}

/// Rebuilds a position by replaying its moves in order.
///
/// Never from a stored FEN. A board is only as trustworthy as the moves that made it, and a cached
/// position is a second copy of the game that can disagree with the log it came from. (The client's
/// library has a second, unrelated reason for the same rule — see `ChessKitContractTests`.)
///
/// Returns null if any move in the log cannot be played, which means this build cannot continue the
/// game. Guessing at it would be worse than stopping.
export function replay(moves: string[]): Chess | null {
  const chess = new Chess();
  for (const move of moves) {
    try {
      chess.move(move);
    } catch {
      return null;
    }
  }
  return chess;
}

/// What the position is now.
export function describe(chess: Chess): ChessPositionState {
  const checkmate = chess.isCheckmate();
  // Ordered, and the order matters. A checkmate is not a draw, and `isDraw()` is true for every
  // drawn ending — so it has to be asked last, once the specific reasons have been ruled out, or
  // every draw would be reported as the fifty-move rule.
  const outcome: ChessOutcome | null = checkmate
    ? "checkmate"
    : chess.isStalemate()
    ? "stalemate"
    : chess.isInsufficientMaterial()
    ? "insufficient_material"
    : chess.isThreefoldRepetition()
    ? "repetition"
    : chess.isDraw()
    ? "fifty_moves"
    : null;

  return {
    finished: chess.isGameOver(),
    outcome,
    hasWinner: checkmate,
    inCheck: chess.inCheck(),
    turn: chess.turn(),
  };
}

/// Whose turn it is, as a player id.
///
/// The initiator is white — the only ordering both devices can derive without being told.
export function playerToMove(chess: Chess, initiatorId: string, otherId: string): string {
  return chess.turn() === "w" ? initiatorId : otherId;
}
