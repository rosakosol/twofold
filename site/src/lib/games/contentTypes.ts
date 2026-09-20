import type { Database } from "@/lib/db/types";

export type GameType = Database["public"]["Enums"]["game_type"];

export type TriviaQuestion = Database["public"]["Tables"]["trivia_questions"]["Row"];
export type MoreLikelyPrompt = Database["public"]["Tables"]["more_likely_prompts"]["Row"];
export type ThisOrThatPrompt = Database["public"]["Tables"]["this_or_that_prompts"]["Row"];
export type DeepConversationTopic = Database["public"]["Tables"]["deep_conversation_topics"]["Row"];
export type DailyQuestion = Database["public"]["Tables"]["daily_questions"]["Row"];
export type GameDeck = Database["public"]["Tables"]["game_decks"]["Row"];

export type ContentRow =
  | TriviaQuestion
  | MoreLikelyPrompt
  | ThisOrThatPrompt
  | DeepConversationTopic
  | DailyQuestion;

export type ContentTypeKey =
  | "trivia_questions"
  | "more_likely_prompts"
  | "this_or_that_prompts"
  | "deep_conversation_topics"
  | "daily_questions";

/** The subset with a `tier` column. The tier statistics are only meaningful for these, and typing
 * them this way means the daily bank cannot be passed to a query that selects `tier` — which would
 * be a PostgREST error at runtime and nothing at all at compile time. */
export type TieredContentTypeKey = Exclude<ContentTypeKey, "daily_questions">;

export interface TextFieldSpec {
  key: string;
  label: string;
  multiline?: boolean;
}

export interface ContentTypeConfig {
  key: ContentTypeKey;
  label: string;
  /** Null for content that belongs to no game type. The daily question bank is the case: it is not
   * a game's deck content, it is its own pool (20261102000000), so there is no `game_type` to
   * associate it with and no deck list to filter by one. */
  gameType: GameType | null;
  /** Whether rows carry a `tier`. False for the daily bank, deliberately — it is open to everyone,
   * and the migration gives it no tier column at all so it cannot be gated later by accident. */
  hasTier?: boolean;
  /** Whether rows belong to a deck. False for the daily bank, which has no decks to belong to. */
  hasDeck?: boolean;
  /** Trivia gets a bespoke options/correct-answer/difficulty block in ContentForm instead
   * of (well, in addition to) the generic textFields loop below — every other content
   * type is genuinely just "one or two plain text fields + category/tier/deck/active",
   * so a shared FieldSpec union just for this one case isn't worth it. */
  isTrivia: boolean;
  textFields: TextFieldSpec[];
  /** How to render this row's main text in the list table. */
  primaryText: (row: ContentRow) => string;
}

export const CONTENT_TYPES: ContentTypeConfig[] = [
  {
    key: "daily_questions",
    label: "Daily Question",
    gameType: null,
    hasTier: false,
    hasDeck: false,
    isTrivia: false,
    textFields: [{ key: "question", label: "Question", multiline: true }],
    primaryText: (row) => (row as DailyQuestion).question,
  },
  {
    key: "deep_conversation_topics",
    label: "Deep Conversations",
    gameType: "deep_conversations",
    hasTier: true,
    hasDeck: true,
    isTrivia: false,
    textFields: [{ key: "topic", label: "Topic", multiline: true }],
    primaryText: (row) => (row as DeepConversationTopic).topic,
  },
  {
    key: "more_likely_prompts",
    label: "More Likely",
    gameType: "more_likely",
    hasTier: true,
    hasDeck: true,
    isTrivia: false,
    textFields: [{ key: "prompt", label: "Prompt", multiline: true }],
    primaryText: (row) => (row as MoreLikelyPrompt).prompt,
  },
  {
    key: "this_or_that_prompts",
    label: "This or That",
    gameType: "this_or_that",
    hasTier: true,
    hasDeck: true,
    isTrivia: false,
    textFields: [
      { key: "option_a", label: "Option A" },
      { key: "option_b", label: "Option B" },
    ],
    primaryText: (row) => {
      const r = row as ThisOrThatPrompt;
      return `${r.option_a} / ${r.option_b}`;
    },
  },
  {
    key: "trivia_questions",
    label: "Trivia",
    gameType: "trivia_battle",
    hasTier: true,
    hasDeck: true,
    isTrivia: true,
    textFields: [{ key: "question", label: "Question", multiline: true }],
    primaryText: (row) => (row as TriviaQuestion).question,
  },
];

/** A row's tier, or null for content from a table that has none.
 *
 * `in` rather than a cast: the daily bank genuinely lacks the column, and a cast would turn a
 * missing value into `undefined` at runtime while claiming otherwise to the compiler. */
export function tierOf(row: ContentRow): string | null {
  return "tier" in row ? ((row as { tier: string | null }).tier ?? null) : null;
}

/** A row's deck, or null for content that belongs to no deck. */
export function deckIdOf(row: ContentRow): string | null {
  return "deck_id" in row ? ((row as { deck_id: string | null }).deck_id ?? null) : null;
}

/** The content types that belong to decks.
 *
 * Anything choosing a game type — the deck editor, chiefly — wants this rather than CONTENT_TYPES,
 * which now also holds the daily question bank and its null `gameType`. Reaching for
 * `CONTENT_TYPES[0]` used to be a safe way to get a default and is not any more. */
export const DECK_CONTENT_TYPES = CONTENT_TYPES.filter(
  (c): c is ContentTypeConfig & { gameType: GameType } => c.gameType !== null,
);

export function contentTypeFor(key: ContentTypeKey): ContentTypeConfig {
  const config = CONTENT_TYPES.find((c) => c.key === key);
  if (!config) throw new Error(`Unknown content type: ${key}`);
  return config;
}

/** Given a deck's game_type, find which content table its questions actually live in —
 * used by the deck detail view (/admin/games/decks/[id]) to know what to query/render. */
export function contentTypeForGameType(gameType: GameType): ContentTypeConfig {
  const config = CONTENT_TYPES.find((c) => c.gameType === gameType);
  if (!config) throw new Error(`Unknown game type: ${gameType}`);
  return config;
}

export const TIER_VALUES = ["plus", "premium"] as const;
export type Tier = (typeof TIER_VALUES)[number];

export const DIFFICULTY_VALUES = ["easy", "medium", "hard"] as const;
export type Difficulty = (typeof DIFFICULTY_VALUES)[number];
