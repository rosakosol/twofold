import type { Metadata } from "next";
import Link from "next/link";
import { HelpCircle } from "lucide-react";
import "./faq.css";
import { FaqBrowser, type FaqBrowserGroup } from "@/components/marketing/FaqBrowser";
import { StatusPill } from "@/components/site/StatusPill";
import { getFaqEntries, groupFaqEntriesByCategory } from "@/lib/marketing/faq";
import { FAQ_FALLBACK, FAQ_CATEGORY_LABELS, FAQ_FALLBACK_CATEGORY_ORDER } from "@/lib/marketing/faqFallback";
import { faqGroupLabel, formatFaqAnswer } from "@/lib/marketing/faqFormat";

export const metadata: Metadata = {
  title: "FAQ",
  description: "Answers to common questions about Twofold: getting started, subscriptions and billing, privacy and data, flight tracking, and trips and memories.",
};

// The FAQ page (docs/TWOFOLD_WEBSITE.md, section 7). Every question and answer is the live copy from
// faq_entries, which the app's Settings > Support screen shares, word for word and in its own
// groups and order; this page only formats it.

/** Short, stable anchors per group. #subscriptions is linked to from elsewhere. */
function anchorFor(category: string) {
  const c = category.toLowerCase();
  if (c.startsWith("getting")) return "getting-started";
  if (c.startsWith("subscription")) return "subscriptions";
  if (c.startsWith("privacy")) return "privacy";
  if (c.startsWith("flight")) return "flights";
  if (c.startsWith("trip")) return "trips";
  return c.replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

export default async function FaqPage() {
  const entries = await getFaqEntries();

  // Empty means the Supabase read failed outright: the static copy stands in rather than a blank page.
  const raw: { category: string; items: { id: string; question: string; answer: string }[] }[] =
    entries.length > 0
      ? groupFaqEntriesByCategory(entries)
      : FAQ_FALLBACK_CATEGORY_ORDER.map((category) => ({
          category: FAQ_CATEGORY_LABELS[category],
          items: FAQ_FALLBACK.filter((item) => item.category === category).map((item) => ({
            id: `${category}-${item.order}`,
            question: item.question,
            answer: item.answer,
          })),
        }));

  const groups: FaqBrowserGroup[] = raw.map((group) => ({
    id: anchorFor(group.category),
    label: faqGroupLabel(group.category),
    items: group.items.map((item) => ({
      id: item.id,
      question: item.question,
      answer: formatFaqAnswer(item.answer),
      answerText: item.answer,
    })),
  }));

  return (
    <>
      <section className="faq-hero" aria-labelledby="faq-title">
        <div className="page-wrap">
          <StatusPill tone="surface" icon={<HelpCircle />}>
            FAQ
          </StatusPill>
          <h1 id="faq-title">Frequently asked questions</h1>
          <p className="lead">
            Can&rsquo;t find what you&rsquo;re looking for? Email{" "}
            <a className="btn-link" href="mailto:support@twofoldapp.com.au">
              support@twofoldapp.com.au
            </a>{" "}
            and a real person will get back to you.
          </p>
        </div>
      </section>

      <section className="faq-main" aria-label="Questions">
        <div className="page-wrap">
          <FaqBrowser groups={groups} />
        </div>
      </section>

      <section className="faq-closing-section" aria-labelledby="faq-closing-title">
        <div className="page-wrap">
          <div className="faq-closing">
            {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size brand mark */}
            <img src="/assets/globe-heart.png" alt="" width={56} height={56} />
            <h2 id="faq-closing-title">Still have a question?</h2>
            <p>
              Email us and a real person will get back to you. Got an idea for Twofold? We read every piece of feedback.
            </p>
            <div className="faq-closing-actions">
              <a className="btn btn-primary" href="mailto:support@twofoldapp.com.au">
                Email support
              </a>
              <Link className="btn btn-secondary" href="/feedback">
                Send feedback
              </Link>
            </div>
          </div>
        </div>
      </section>
    </>
  );
}
