import type { Metadata } from "next";
import { getFaqItems, type FaqItemDoc } from "@/lib/marketing/sanity";
import { FAQ_FALLBACK, FAQ_CATEGORY_LABELS } from "@/lib/marketing/faqFallback";
import { FaqAccordionItem } from "@/components/marketing/FaqAccordionItem";
import { Reveal } from "@/components/marketing/Reveal";

export const metadata: Metadata = {
  title: "FAQ",
  description: "Answers to common questions about Twofold: platforms, subscriptions, billing, privacy, and how partner connections work.",
};

const CATEGORY_ORDER: FaqItemDoc["category"][] = ["getting-started", "subscriptions", "privacy"];

export default async function FaqPage() {
  const sanityItems = await getFaqItems();

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
          {CATEGORY_ORDER.map((category, categoryIndex) => {
            const fromSanity = sanityItems.filter((item) => item.category === category);
            const items = fromSanity.length > 0 ? fromSanity : FAQ_FALLBACK.filter((item) => item.category === category);
            return (
              <Reveal key={category} className="faq-group" id={category === "subscriptions" ? "subscriptions" : undefined}>
                <h2>{FAQ_CATEGORY_LABELS[category]}</h2>
                <div className="acc-list">
                  {items.map((item, index) => (
                    <FaqAccordionItem
                      key={item.question}
                      question={item.question}
                      answer={item.answer}
                      defaultOpen={categoryIndex === 0 && index === 0}
                    />
                  ))}
                </div>
              </Reveal>
            );
          })}
        </div>
      </section>
    </>
  );
}
