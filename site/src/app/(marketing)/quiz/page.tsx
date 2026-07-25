import type { Metadata } from "next";
import Link from "next/link";
import { RelationshipQuiz } from "@/components/marketing/RelationshipQuiz";
import { isQuizPlayable } from "@/lib/marketing/quiz";
import { getQuizQuestions, getQuizResults } from "@/lib/marketing/sanity";

export const metadata: Metadata = {
  title: "Which plan fits your relationship?",
  description: "Answer a few quick questions and we'll point you to the Twofold plan that fits how you two do long distance.",
};

export default async function QuizPage() {
  const [questions, results] = await Promise.all([getQuizQuestions(), getQuizResults()]);

  // RelationshipQuiz itself renders nothing once there are fewer than 2 published
  // questions (each with 2+ options) — deliberately so on the home page, where the quiz
  // is just one of several sections. As this page's *entire* content, that would be a
  // blank page with no way to tell why, so show a real message instead.
  if (!isQuizPlayable(questions)) {
    return (
      <section style={{ textAlign: "center" }}>
        <div className="wrap-narrow">
          <p className="eyebrow" style={{ justifyContent: "center" }}>Find your fit</p>
          <h1>The quiz is still being put together</h1>
          <p className="lede" style={{ margin: "0 auto 24px" }}>
            Check back soon — or just compare plans directly.
          </p>
          <Link href="/pricing" className="btn btn-primary btn-lg">
            See pricing
          </Link>
        </div>
      </section>
    );
  }

  // No extra wrapper here — RelationshipQuiz renders its own top-level <section>, which
  // already gets the standard 84px vertical page padding from the generic `section` rule
  // in marketing.css; wrapping it again would double that spacing.
  return <RelationshipQuiz questions={questions} results={results} />;
}
