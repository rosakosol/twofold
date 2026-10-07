"use client";

import { useEffect, useMemo, useState, type ReactNode } from "react";
import { Search } from "lucide-react";
import { AccordionItem } from "@/components/site/Accordion";

export interface FaqBrowserGroup {
  /** The anchor: #getting-started, #subscriptions... */
  id: string;
  label: string;
  items: { id: string; question: string; answer: ReactNode; answerText: string }[];
}

/**
 * The FAQ's questions (docs/TWOFOLD_WEBSITE.md, section 7): a search that filters them as you type,
 * the topic list beside them (sticky on a desktop, scrolling chips on a phone) with the group in
 * view marked, and an accordion per group with its first question open.
 *
 * The answers arrive formatted from the server; `answerText` is the same answer as plain text, for
 * the search to match against.
 */
export function FaqBrowser({ groups }: { groups: FaqBrowserGroup[] }) {
  const [query, setQuery] = useState("");
  const [currentId, setCurrentId] = useState(groups[0]?.id);
  const needle = query.trim().toLowerCase();

  const visible = useMemo(() => {
    if (!needle) return groups;
    return groups
      .map((group) => ({
        ...group,
        items: group.items.filter(
          (item) => item.question.toLowerCase().includes(needle) || item.answerText.toLowerCase().includes(needle)
        ),
      }))
      .filter((group) => group.items.length > 0);
  }, [groups, needle]);
  const matchCount = visible.reduce((n, group) => n + group.items.length, 0);

  // Marks the topic whose group is in view: the last group whose top has passed the header.
  useEffect(() => {
    const sections = visible.map((group) => document.getElementById(group.id)).filter(Boolean) as HTMLElement[];
    if (!sections.length) return;
    function update() {
      let current = sections[0].id;
      for (const section of sections) {
        if (section.getBoundingClientRect().top <= 140) current = section.id;
      }
      setCurrentId(current);
    }
    update();
    window.addEventListener("scroll", update, { passive: true });
    return () => window.removeEventListener("scroll", update);
  }, [visible]);

  return (
    <div className="faq-browser">
      <div className="faq-search">
        <label className="sr-only" htmlFor="faq-search">
          Search questions
        </label>
        <Search aria-hidden />
        <input
          id="faq-search"
          className="input"
          type="search"
          placeholder={'Search questions, like "cancel" or "export"'}
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          aria-describedby="faq-search-status"
        />
      </div>
      <p id="faq-search-status" className="faq-search-status" role="status" aria-live="polite">
        {needle ? (matchCount ? `${matchCount} ${matchCount === 1 ? "question matches" : "questions match"} “${query.trim()}”` : `No questions match “${query.trim()}”. Try another word, or email us.`) : ""}
      </p>

      <div className="faq-layout">
        <nav className="faq-topics" aria-label="FAQ topics">
          <ul>
            {visible.map((group) => (
              <li key={group.id}>
                <a href={`#${group.id}`} aria-current={currentId === group.id ? "true" : undefined}>
                  <span>{group.label}</span>
                  <span className="faq-topic-count" aria-label={`${group.items.length} questions`}>
                    {group.items.length}
                  </span>
                </a>
              </li>
            ))}
          </ul>
        </nav>

        <div className="faq-groups">
          {visible.map((group) => (
            <section key={group.id} id={group.id} className="faq-group" aria-labelledby={`${group.id}-title`}>
              <h2 id={`${group.id}-title`}>{group.label}</h2>
              <div className="accordion">
                {group.items.map((item, index) => (
                  // Keyed by the search, so a filtered list opens every match, and clearing it
                  // goes back to the first question of each group open.
                  <AccordionItem key={`${item.id}-${needle}`} title={item.question} defaultOpen={needle ? true : index === 0}>
                    {item.answer}
                  </AccordionItem>
                ))}
              </div>
            </section>
          ))}
        </div>
      </div>
    </div>
  );
}
