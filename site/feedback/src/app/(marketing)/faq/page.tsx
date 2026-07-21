import type { Metadata } from "next";
import { getFaqItems, type FaqItemDoc } from "@/lib/marketing/sanity";
import { FAQ_FALLBACK, FAQ_CATEGORY_LABELS } from "@/lib/marketing/faqFallback";

export const metadata: Metadata = {
  title: "FAQ",
  description: "Answers to common questions about Twofold: platforms, subscriptions, billing, privacy, and how partner connections work.",
};

const CATEGORY_ORDER: FaqItemDoc["category"][] = ["getting-started", "subscriptions", "privacy"];

function FaqAccordion({ items, defaultOpenFirst }: { items: FaqItemDoc[]; defaultOpenFirst?: boolean }) {
  return (
    <div className="faq-list" style={{ marginBottom: 48 }}>
      {items.map((item, index) => (
        <details key={item.question} className="faq-item" open={defaultOpenFirst && index === 0}>
          <summary>
            {item.question}
            <svg className="icon icon-chevron">
              <use href="/assets/icons.svg#icon-chevron-down" />
            </svg>
          </summary>
          <div className="faq-body">{item.answer}</div>
        </details>
      ))}
    </div>
  );
}

export default async function FaqPage() {
  const sanityItems = await getFaqItems();

  return (
    <>
      <section className="page-hero">
        <p className="eyebrow">
          <svg className="icon">
            <use href="/assets/icons.svg#icon-sparkle" />
          </svg>
          FAQ
        </p>
        <h1>Frequently asked questions</h1>
        <p>
          Can&apos;t find what you&apos;re looking for?{" "}
          <a className="text-link" href="mailto:hello@twofoldapp.com.au">
            Email us
          </a>{" "}
          — a real person will get back to you.
        </p>
      </section>

      <section>
        <div className="wrap-narrow">
          {CATEGORY_ORDER.map((category, categoryIndex) => {
            const fromSanity = sanityItems.filter((item) => item.category === category);
            const items = fromSanity.length > 0 ? fromSanity : FAQ_FALLBACK.filter((item) => item.category === category);
            return (
              <div key={category} id={category === "subscriptions" ? "subscriptions" : undefined}>
                <h2 style={{ marginBottom: 16 }}>{FAQ_CATEGORY_LABELS[category]}</h2>
                <FaqAccordion items={items} defaultOpenFirst={categoryIndex === 0} />
              </div>
            );
          })}
        </div>
      </section>

      <section aria-labelledby="cta-heading">
        <div className="cta-banner reveal">
          <h2 id="cta-heading">Still have a question?</h2>
          <p>We read every email — reach out and we&apos;ll get back to you.</p>
          <div className="cta-row">
            <a className="btn btn-dark btn-lg" href="mailto:hello@twofoldapp.com.au">
              Email us
            </a>
          </div>
        </div>
      </section>
    </>
  );
}
