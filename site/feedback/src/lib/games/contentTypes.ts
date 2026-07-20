import type { Database } from "@/lib/db/types";

export type GameType = Database["public"]["Enums"]["game_type"];

export type TriviaQuestion = Database["public"]["Tables"]["trivia_questions"]["Row"];
export type MoreLikelyPrompt = Database["public"]["Tables"]["more_likely_prompts"]["Row"];
export type ThisOrThatPrompt = Database["public"]["Tables"]["this_or_that_prompts"]["Row"];
export type DeepConversationTopic = Database["public"]["Tables"]["deep_conversation_topics"]["Row"];
export type GameDeck = Database["public"]["Tables"]["game_decks"]["Row"];

export type ContentRow = TriviaQuestion | MoreLikelyPrompt | ThisOrThatPrompt | DeepConversationTopic;

export type ContentTypeKey =
  | "trivia_questions"
  | "more_likely_prompts"
  | "this_or_that_prompts"
  | "deep_conversation_topics";

export interface TextFieldSpec {
  key: string;
  label: string;
  multiline?: boolean;
}

export interface ContentTypeConfig {
  key: ContentTypeKey;
  label: string;
  gameType: GameType;
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
    key: "deep_conversation_topics",
    label: "Deep Conversations",
    gameType: "deep_conversations",
    isTrivia: false,
    textFields: [{ key: "topic", label: "Topic", multiline: true }],
    primaryText: (row) => (row as DeepConversationTopic).topic,
  },
  {
    key: "more_likely_prompts",
    label: "More Likely",
    gameType: "more_likely",
    isTrivia: false,
    textFields: [{ key: "prompt", label: "Prompt", multiline: true }],
    primaryText: (row) => (row as MoreLikelyPrompt).prompt,
  },
  {
    key: "this_or_that_prompts",
    label: "This or That",
    gameType: "this_or_that",
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
    isTrivia: true,
    textFields: [{ key: "question", label: "Question", multiline: true }],
    primaryText: (row) => (row as TriviaQuestion).question,
  },
];

export function contentTypeFor(key: ContentTypeKey): ContentTypeConfig {
  const config = CONTENT_TYPES.find((c) => c.key === key);
  if (!config) throw new Error(`Unknown content type: ${key}`);
  return config;
}

export const TIER_VALUES = ["plus", "premium"] as const;
export type Tier = (typeof TIER_VALUES)[number];

export const DIFFICULTY_VALUES = ["easy", "medium", "hard"] as const;
export type Difficulty = (typeof DIFFICULTY_VALUES)[number];
