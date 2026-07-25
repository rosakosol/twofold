import type { Metadata } from "next";
import { RelationshipQuiz } from "@/components/marketing/RelationshipQuiz";
import { getQuizQuestions, getQuizResults } from "@/lib/marketing/sanity";

export const metadata: Metadata = {
  title: "Which plan fits your relationship?",
  description: "Answer a few quick questions and we'll point you to the Twofold plan that fits how you two do long distance.",
};

export default async function QuizPage() {
  const [questions, results] = await Promise.all([getQuizQuestions(), getQuizResults()]);
  // No extra wrapper here — RelationshipQuiz renders its own top-level <section>, which
  // already gets the standard 84px vertical page padding from the generic `section` rule
  // in marketing.css; wrapping it again would double that spacing.
  return <RelationshipQuiz questions={questions} results={results} />;
}
