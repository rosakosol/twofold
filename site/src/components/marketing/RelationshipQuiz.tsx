"use client";

import { useMemo, useRef, useState } from "react";
import Link from "next/link";
import { Reveal } from "@/components/marketing/Reveal";
import { isQuizPlayable } from "@/lib/marketing/quiz";
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
    description: "Unlimited trips and memories, up to 5 tracked flights a month, and 500+ questions and games - everything most long-distance couples need.",
    ctaLabel: "Get Twofold Plus",
  },
  premium: {
    title: "Twofold Premium sounds like your fit",
    // TEMP: the Relationship Record PDF export is dropped from this list while the feature is
    // pulled from the first release - see featuresFallback.ts. The live copy is the
    // `quizResult-premium` doc in Studio.
    description: "The full relationship globe experience - more flight tracking, 2000+ questions and games, and the interactive 3D globe.",
    ctaLabel: "Get Twofold Premium",
  },
};

/** Port of the old site's assets/js/cms-quiz.js - same state machine (question index +
 * answers array), just as React state instead of manual DOM rebuilds. Renders nothing
 * (matches the original's `hidden` section) if there aren't at least 2 published
 * questions with options, since there's no sensible hardcoded fallback for a quiz. */
export function RelationshipQuiz({
  questions,
  results,
  autoStart = false,
}: {
  questions: QuizQuestionDoc[];
  results: { plus: QuizResultDoc | null; premium: QuizResultDoc | null };
  /**
   * Skip the "Take the quiz" card and open on question 1. On for /quiz, where the visitor
   * navigated specifically to take it; off on the home page, where the quiz is one section
   * among many and shouldn't read as a half-answered form to someone scrolling past.
   */
  autoStart?: boolean;
}) {
  const [started, setStarted] = useState(autoStart);
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
  const isPlayable = isQuizPlayable(questions);

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
    // Back to whichever state this instance opened in - the start card on the home page,
    // question 1 on /quiz.
    setStarted(autoStart);
  }

  const result = resolvedResults[plan];
  const question = questions[currentIndex];

  // The red gradient start card. Self-contained (its own eyebrow and heading) rather than
  // sitting under the section-head the started states use, because that's the shape it had
  // as the standalone "quiz isn't ready yet" teaser on the home page - see page.tsx, which
  // still renders the same card for that case. Deliberately NOT wrapped in <Reveal>: its
  // "is-visible" class is added outside React's tracking by an IntersectionObserver, so
  // after the observer has already fired once, re-rendering this card on "Retake quiz"
  // would bring it back at opacity 0.
  if (!started) {
    return (
      <section id="quiz" aria-labelledby="quiz-start-heading">
        <div className="wrap quiz-teaser-wrap">
          <div className="card quiz-teaser-card">
            <p className="eyebrow" style={{ justifyContent: "center" }}>
              <svg className="icon">
                <use href="/assets/icons.svg#icon-sparkle" />
              </svg>
              Find your fit
            </p>
            <h2 id="quiz-start-heading">Which plan fits your relationship?</h2>
            <p>
              Answer {questions.length} quick questions and we&apos;ll point you to the plan that matches how you two do
              long distance.
            </p>
            <button type="button" className="btn btn-white btn-lg" onClick={() => setStarted(true)}>
              Take the quiz
              <svg className="icon">
                <use href="/assets/icons.svg#icon-arrow-right" />
              </svg>
            </button>
          </div>
        </div>
      </section>
    );
  }

  return (
    <section id="quiz" aria-labelledby="quiz-heading">
      <div className="wrap">
        <Reveal className="section-head">
          <p className="eyebrow">
            <svg className="icon">
              <use href="/assets/icons.svg#icon-sparkle" />
            </svg>
            Find your fit
          </p>
          <h2 id="quiz-heading">Which plan fits your relationship?</h2>
          <p>Answer a few quick questions and we&apos;ll point you to the plan that matches how you two do long distance.</p>
        </Reveal>

        {/* Neither card below uses the scroll-triggered .reveal treatment - both are
            driven directly by clicking an answer, not by scrolling down to discover
            them for the first time. They also sit at the same position in this ternary,
            so React reuses one underlying DOM node between the two; .reveal's manually-
            added "is-visible" class (added outside React's own tracking, by an
            IntersectionObserver callback) would otherwise get wiped the moment React
            re-renders that reused node with the other branch's className - which reads
            as the result card fading back out right after it appears. */}
        {!showResult ? (
          <div className="quiz-card">
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
          <div ref={resultRef} className="quiz-card quiz-result">
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
