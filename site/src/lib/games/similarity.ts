import type { ContentRow, ContentTypeConfig, ThisOrThatPrompt, TriviaQuestion } from "@/lib/games/contentTypes";

export interface SimilarPair {
  a: ContentRow;
  b: ContentRow;
  score: number;
}

export interface ContentIssue {
  row: ContentRow;
  reason: string;
}

const SIMILARITY_THRESHOLD = 0.6;
const MIN_TOKENS_TO_COMPARE = 2;

// Short, high-frequency words that would otherwise dominate similarity scores across unrelated
// prompts sharing the same template (e.g. "what's your favorite...", "have you ever...").
const STOPWORDS = new Set([
  "a", "an", "the", "of", "to", "in", "on", "at", "is", "are", "was", "were", "be", "been",
  "and", "or", "but", "if", "your", "you", "my", "i", "me", "we", "us", "do", "does", "did",
  "have", "has", "had", "would", "will", "can", "could", "should", "with", "for", "about",
  "this", "that", "it", "its", "their", "them", "what", "which", "who",
]);

function normalize(text: string): string {
  return text
    .toLowerCase()
    .trim()
    .replace(/[^\p{L}\p{N}\s]/gu, "")
    .replace(/\s+/g, " ");
}

function tokenSet(text: string): Set<string> {
  return new Set(
    normalize(text)
      .split(" ")
      .filter((w) => w.length > 0 && !STOPWORDS.has(w))
  );
}

function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0;
  let intersection = 0;
  for (const token of a) {
    if (b.has(token)) intersection++;
  }
  const union = a.size + b.size - intersection;
  return union === 0 ? 0 : intersection / union;
}

/** Pairwise-compares every entry's primary text within one game type and flags near-duplicate
 * wording. O(n^2) but token sets are tiny and admin content sets are small (low hundreds), so
 * this runs client-side instantly without needing a search index. */
export function findSimilarPairs(rows: ContentRow[], contentType: ContentTypeConfig): SimilarPair[] {
  const entries = rows.map((row) => {
    const text = contentType.primaryText(row);
    return { row, normalized: normalize(text), tokens: tokenSet(text) };
  });

  const pairs: SimilarPair[] = [];
  for (let i = 0; i < entries.length; i++) {
    for (let j = i + 1; j < entries.length; j++) {
      const x = entries[i];
      const y = entries[j];
      if (x.normalized === y.normalized) {
        pairs.push({ a: x.row, b: y.row, score: 1 });
        continue;
      }
      if (x.tokens.size < MIN_TOKENS_TO_COMPARE || y.tokens.size < MIN_TOKENS_TO_COMPARE) continue;
      const score = jaccard(x.tokens, y.tokens);
      if (score >= SIMILARITY_THRESHOLD) pairs.push({ a: x.row, b: y.row, score });
    }
  }

  return pairs.sort((a, b) => b.score - a.score);
}

function triviaOptionsOf(row: TriviaQuestion): string[] {
  return Array.isArray(row.options) && row.options.every((o) => typeof o === "string")
    ? (row.options as string[])
    : [];
}

/** Structural problems similarity scoring can't catch — a trivia answer that doesn't match any
 * option, duplicate options, identical this-or-that choices, blank/near-blank text. */
export function findContentIssues(rows: ContentRow[], contentType: ContentTypeConfig): ContentIssue[] {
  const issues: ContentIssue[] = [];

  for (const row of rows) {
    const text = contentType.primaryText(row);
    const wordCount = normalize(text).split(" ").filter(Boolean).length;
    if (wordCount === 0) {
      issues.push({ row, reason: "Empty text" });
    } else if (wordCount < 3) {
      issues.push({ row, reason: "Very short text — check it isn't a placeholder" });
    }
    if (!row.category?.trim()) {
      issues.push({ row, reason: "Missing category" });
    }

    if (contentType.isTrivia) {
      const trivia = row as TriviaQuestion;
      const options = triviaOptionsOf(trivia);
      const normalizedOptions = options.map(normalize);
      const uniqueOptions = new Set(normalizedOptions);
      if (options.length < 2) {
        issues.push({ row, reason: "Fewer than 2 answer options" });
      } else if (uniqueOptions.size !== normalizedOptions.length) {
        issues.push({ row, reason: "Duplicate answer options" });
      }
      if (!options.includes(trivia.correct_answer)) {
        issues.push({ row, reason: "Correct answer isn't among the listed options" });
      }
    }

    if (contentType.key === "this_or_that_prompts") {
      const thisOrThat = row as ThisOrThatPrompt;
      if (normalize(thisOrThat.option_a) === normalize(thisOrThat.option_b)) {
        issues.push({ row, reason: "Option A and Option B are the same" });
      }
    }
  }

  return issues;
}
