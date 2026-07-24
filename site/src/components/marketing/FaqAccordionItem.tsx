"use client";

import { useState } from "react";

/** Matches design_handoff_twofold_site/faq.html's .acc-item exactly — a button-driven
 * max-height transition + rotating chevron, not the native <details>/<summary> the
 * previous implementation used. */
export function FaqAccordionItem({
  question,
  answer,
  defaultOpen = false,
}: {
  question: string;
  answer: string;
  defaultOpen?: boolean;
}) {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <div className={`acc-item${open ? " open" : ""}`}>
      <button type="button" className="acc-q" onClick={() => setOpen((v) => !v)} aria-expanded={open}>
        {question}
        <svg className="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
          <path d="M6 9l6 6 6-6" />
        </svg>
      </button>
      <div className="acc-a">
        <p>{answer}</p>
      </div>
    </div>
  );
}
