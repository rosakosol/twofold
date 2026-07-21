"use client";

import { useMemo, useRef, useState } from "react";
import Link from "next/link";
import type { QuizQuestionDoc, QuizResultDoc } from "@/lib/marketing/sanity";

const LEAN_WEIGHTS: Record<string, number> = {
  strong_plus: -2,
  plus: -1,
  neutral: 0,
  premium: 1,
  strong_premium: 2,
};

const FALLBACK_RESULTS: Record<"plus" | "premium", QuizResultDoc> = {
  plus: {
    title: "Twofold Plus sounds like your fit",
    description: "Unlimited trips and memories, up to 5 tracked flights a month, and 500+ questions and games — everything most long-distance couples need.",
    ctaLabel: "Get Twofold Plus",
  },
  premium: {
    title: "Twofold Premium sounds like your fit",
    description: "The full relationship globe experience — more flight tracking, 2000+ questions and games, the interactive 3D globe, and the Relationship Record PDF export.",
    ctaLabel: "Get Twofold Premium",
  },
};

/** Port of the old site's assets/js/cms-quiz.js — same state machine (question index +
 * answers array), just as React state instead of manual DOM rebuilds. Renders nothing
 * (matches the original's `hidden` section) if there aren't at least 2 published
 * questions with options, since there's no sensible hardcoded fallback for a quiz. */
export function RelationshipQuiz({
  questions,
  results,
}: {
  questions: QuizQuestionDoc[];
  results: { plus: QuizResultDoc | null; premium: QuizResultDoc | null };
}) {
  const [answers, setAnswers] = useState<string[]>([]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [showResult, setShowResult] = useState(false);
  const resultRef = useRef<HTMLDivElement>(null);

  const resolvedResults = useMemo(
    () => ({ plus: results.plus ?? FALLBACK_RESULTS.plus, premium: results.premium ?? FALLBACK_RESULTS.premium }),
    [results]
  );

  // Every hook above must run unconditionally on every render (Rules of Hooks), so the
  // "not enough content to show a quiz" bail-out has to come after them, not before.
  const isPlayable = questions.length >= 2 && questions.every((q) => q.options.length >= 2);

  const plan: "plus" | "premium" = useMemo(() => {
    const score = answers.reduce((sum, lean) => sum + (LEAN_WEIGHTS[lean] ?? 0), 0);
    return score > 0 ? "premium" : "plus";
  }, [answers]);

  if (!isPlayable) return null;

  function selectAnswer(lean: string) {
    const next = [...answers.slice(0, currentIndex), lean];
    setAnswers(next);
    if (currentIndex + 1 < questions.length) {
      setCurrentIndex(currentIndex + 1);
    } else {
      setShowResult(true);
      requestAnimationFrame(() => resultRef.current?.scrollIntoView({ behavior: "smooth", block: "center" }));
    }
  }

  function goBack() {
    if (currentIndex === 0) return;
    setCurrentIndex(currentIndex - 1);
    setShowResult(false);
  }

  function retake() {
    setAnswers([]);
    setCurrentIndex(0);
    setShowResult(false);
  }

  const result = resolvedResults[plan];
  const question = questions[currentIndex];

  return (
    <section id="quiz" aria-labelledby="quiz-heading">
      <div className="wrap-narrow">
        <div className="section-head reveal">
          <p className="eyebrow">
            <svg className="icon">
              <use href="/assets/icons.svg#icon-sparkle" />
            </svg>
            Find your fit
          </p>
          <h2 id="quiz-heading">Which plan fits your relationship?</h2>
          <p>Answer a few quick questions and we&apos;ll point you to the plan that matches how you two do long distance.</p>
        </div>

        {!showResult ? (
          <div className="quiz-card reveal">
            <div className="quiz-progress">
              {questions.map((q, index) => (
                <span key={q.question} className={`dot${index < currentIndex ? " is-done" : ""}${index === currentIndex ? " is-current" : ""}`} />
              ))}
            </div>
            <h3 className="quiz-question-text">{question.question}</h3>
            <div className="quiz-options">
              {question.options.map((option) => (
                <button
                  key={option.label}
                  type="button"
                  className={`quiz-option${answers[currentIndex] === option.lean ? " is-selected" : ""}`}
                  onClick={() => selectAnswer(option.lean)}
                >
                  {option.label}
                </button>
              ))}
            </div>
            <div className="quiz-nav">
              <button type="button" className="btn btn-ghost btn-sm" disabled={currentIndex === 0} onClick={goBack}>
                Back
              </button>
            </div>
          </div>
        ) : (
          <div ref={resultRef} className="quiz-card quiz-result reveal">
            <p className="eyebrow" style={{ justifyContent: "center" }}>
              <svg className="icon">
                <use href="/assets/icons.svg#icon-check-circle" />
              </svg>
              Your match
            </p>
            <h3>{result.title}</h3>
            <p>{result.description}</p>
            <Link className="btn btn-primary btn-lg" href={`/pricing?plan=${plan}`}>
              {result.ctaLabel}
            </Link>
            <p style={{ marginTop: 16 }}>
              <button type="button" className="text-link" style={{ background: "none", border: "none", cursor: "pointer" }} onClick={retake}>
                Retake quiz
              </button>
            </p>
          </div>
        )}
      </div>
    </section>
  );
}
