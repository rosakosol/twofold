import type { QuizQuestionDoc } from "@/lib/marketing/sanity";

/** At least 2 questions, each with at least 2 answer options — matches the schema's own
 * `Rule.min(2)` on `options`, but a question can still be saved as a Sanity draft (not
 * published) or published with only 1 option filled in, either of which this catches.
 * Lives outside RelationshipQuiz.tsx (a "use client" module) specifically so the page
 * routes — Server Components — can call it directly instead of only rendering it. */
export function isQuizPlayable(questions: QuizQuestionDoc[]): boolean {
  return questions.length >= 2 && questions.every((q) => q.options.length >= 2);
}
