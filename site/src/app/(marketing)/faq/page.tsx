import type { Metadata } from "next";
import { getFaqEntries, groupFaqEntriesByCategory } from "@/lib/marketing/faq";
import { FAQ_FALLBACK, FAQ_CATEGORY_LABELS } from "@/lib/marketing/faqFallback";
import { FaqAccordionItem } from "@/components/marketing/FaqAccordionItem";
import { Reveal } from "@/components/marketing/Reveal";

export const metadata: Metadata = {
  title: "FAQ",
  description: "Answers to common questions about Twofold: platforms, subscriptions, billing, privacy, and how partner connections work.",
};

// The footer's "Manage subscription" link (components/layout/SiteFooter.tsx) points at
// /faq#subscriptions — matched by category label, not a fixed category id, since faq_entries'
// category column is free text rather than a Sanity-style fixed enum.
const SUBSCRIPTIONS_ANCHOR_LABEL = "Subscriptions & billing";

export default async function FaqPage() {
  const entries = await getFaqEntries();

  // Empty means the Supabase fetch failed outright (see getFaqEntries's own doc comment) —
  // fall back to the same static copy the old Sanity-backed page used for the equivalent case,
  // rather than rendering a blank FAQ page.
  const groups =
    entries.length > 0
      ? groupFaqEntriesByCategory(entries)
      : (["getting-started", "subscriptions", "privacy"] as const).map((category) => ({
          category: FAQ_CATEGORY_LABELS[category],
          items: FAQ_FALLBACK.filter((item) => item.category === category).map((item) => ({
            id: `${category}-${item.order}`,
            category: FAQ_CATEGORY_LABELS[category],
            question: item.question,
            answer: item.answer,
            sortOrder: item.order,
          })),
        }));

  return (
    <>
      <header className="page-head">
        <Reveal className="wrap">
          <span className="eyebrow">
            <svg className="icon">
              <use href="/assets/icons.svg#icon-sparkle" />
            </svg>
            FAQ
          </span>
          <h1>Frequently asked questions</h1>
          <p className="lead">
            Can&apos;t find what you&apos;re looking for?{" "}
            <a className="text-link" href="mailto:hello@twofoldapp.com.au" style={{ display: "inline-flex" }}>
              Email us
            </a>{" "}
            — a real person will get back to you.
          </p>
        </Reveal>
      </header>

      <section style={{ paddingTop: 20 }}>
        <div className="wrap faq-wrap">
          {groups.map((group, groupIndex) => (
            <Reveal
              key={group.category}
              className="faq-group"
              id={group.category === SUBSCRIPTIONS_ANCHOR_LABEL ? "subscriptions" : undefined}
            >
              <h2>{group.category}</h2>
              <div className="acc-list">
                {group.items.map((item, index) => (
                  <FaqAccordionItem
                    key={item.id}
                    question={item.question}
                    answer={item.answer}
                    defaultOpen={groupIndex === 0 && index === 0}
                  />
                ))}
              </div>
            </Reveal>
          ))}
        </div>
      </section>
    </>
  );
}
