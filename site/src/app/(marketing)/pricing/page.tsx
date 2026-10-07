import type { Metadata } from "next";
import Link from "next/link";
import { Check, Minus } from "lucide-react";
import "./pricing.css";
import { PricingClient } from "@/components/marketing/PricingClient";
import { AccordionItem } from "@/components/site/Accordion";
import { getResolvedPlans } from "@/lib/marketing/sanity";
import { getFaqEntries } from "@/lib/marketing/faq";
import { FAQ_FALLBACK } from "@/lib/marketing/faqFallback";
import { formatFaqAnswer } from "@/lib/marketing/faqFormat";

export const metadata: Metadata = {
  title: "Pricing",
  description: "Twofold Plus and Premium. Either partner subscribes and you both get everything. Start with 14 days free.",
};

// The pricing page (docs/TWOFOLD_WEBSITE.md, section 6). The plans, the billing toggle and the
// checkout are PricingClient; this adds the comparison table, the quiz banner and the questions.

type Cell = string | boolean;
const COMPARE: { feature: string; plus: Cell; premium: Cell }[] = [
  { feature: "Trips and memories", plus: "Unlimited", premium: "Unlimited" },
  { feature: "Flights tracked live each month", plus: "2", premium: "5" },
  { feature: "Save flights to your trips", plus: "Unlimited", premium: "Unlimited" },
  { feature: "Delay analysis, gate and aircraft details", plus: false, premium: true },
  { feature: "Questions and conversation starters", plus: "500+", premium: "2000+" },
  { feature: "Sudoku", plus: true, premium: "Every difficulty" },
  { feature: "Word Guess", plus: "Daily limit", premium: "No limit" },
  { feature: "Word Search and Connect 4", plus: false, premium: true },
  { feature: "Relationship Record export", plus: false, premium: true },
  { feature: "Monthly streak repair", plus: false, premium: true },
  { feature: "Home Screen and Lock Screen widgets", plus: true, premium: true },
  { feature: "Smart Rotating widget", plus: false, premium: true },
  { feature: "Drawing Pad and Time and Weather, medium size", plus: false, premium: true },
];

function CompareCell({ value }: { value: Cell }) {
  if (value === true) {
    return (
      <td>
        <Check className="compare-yes" aria-label="Included" role="img" />
      </td>
    );
  }
  if (value === false) {
    return (
      <td>
        <Minus className="compare-no" aria-label="Not included" role="img" />
      </td>
    );
  }
  return <td>{value}</td>;
}

/** The five pricing questions, answered from the live FAQ (faq_entries, shared with the app),
 *  word for word. */
const PRICING_QUESTIONS = [
  "Does one subscription cover both partners?",
  "Can I subscribe on the web instead of in the app?",
  "How do I cancel or manage my subscription?",
  "What happens to my trips and memories if my subscription ends?",
  "Is my payment secure?",
];

export default async function PricingPage() {
  const [plans, faqEntries] = await Promise.all([getResolvedPlans(), getFaqEntries()]);
  // The static fallback stands in only if the live table cannot be read.
  const entries: { question: string; answer: string }[] = (faqEntries.length ? faqEntries : FAQ_FALLBACK).map(
    ({ question, answer }) => ({ question, answer })
  );
  const questions = PRICING_QUESTIONS.map((q) =>
    entries.find((entry) => entry.question.trim().toLowerCase() === q.toLowerCase())
  ).filter((entry): entry is { question: string; answer: string } => Boolean(entry));

  return (
    <>
      <PricingClient plans={plans} />

      <section id="compare" className="pricing-section" aria-labelledby="compare-title">
        <div className="page-wrap">
          <h2 id="compare-title" className="pricing-section-title">
            Compare plans in full
          </h2>
          {/* Scrolls inside itself on a narrow phone rather than widening the page. */}
          <div className="compare-scroll" tabIndex={0} role="group" aria-labelledby="compare-title">
            <table className="compare-table">
              <thead>
                <tr>
                  <th scope="col">Feature</th>
                  <th scope="col">Plus</th>
                  <th scope="col">Premium</th>
                </tr>
              </thead>
              <tbody>
                {COMPARE.map((row) => (
                  <tr key={row.feature}>
                    <th scope="row">{row.feature}</th>
                    <CompareCell value={row.plus} />
                    <CompareCell value={row.premium} />
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <section className="pricing-section" aria-labelledby="deciding-title">
        <div className="page-wrap">
          <div className="pricing-quiz">
            <div>
              <h2 id="deciding-title">Still deciding?</h2>
              <p>Answer five quick questions about how you two do long distance and we&rsquo;ll point you to the right plan.</p>
            </div>
            <Link className="btn btn-primary" href="/quiz">
              Take the quiz
            </Link>
          </div>
        </div>
      </section>

      {questions.length > 0 && (
        <section className="pricing-section" aria-labelledby="pricing-faq-title">
          <div className="page-wrap pricing-faq">
            <h2 id="pricing-faq-title" className="pricing-section-title">
              Questions about pricing
            </h2>
            <div className="accordion">
              {questions.map((entry, i) => (
                <AccordionItem key={entry.question} title={entry.question} defaultOpen={i === 0}>
                  {formatFaqAnswer(entry.answer)}
                </AccordionItem>
              ))}
            </div>
            <p className="pricing-more">
              Something else?{" "}
              <Link className="btn-link" href="/support">
                Contact us
              </Link>
            </p>
          </div>
        </section>
      )}
    </>
  );
}
