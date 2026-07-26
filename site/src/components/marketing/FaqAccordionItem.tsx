"use client";

import { useEffect, useRef, useState } from "react";

/**
 * A button-driven expand/collapse with a rotating chevron.
 *
 * The panel animates on `max-height`, which can't transition to `auto` — so the target height
 * is measured from the content and applied inline, rather than hardcoded in CSS. An earlier
 * version capped it at a fixed 320px, which silently clipped any longer answer; these are
 * editor-written through the Studio FAQ tool, so that would have surfaced as truncated text
 * with no warning. Measuring removes the cap entirely, and the value is released to `none`
 * once the transition finishes, so a later reflow — font swap, rotation, resize — can grow the
 * panel freely instead of being pinned to a stale pixel height.
 *
 * (A `grid-template-rows: 0fr → 1fr` transition would express this in pure CSS, but not every
 * engine collapses a 0fr row inside an auto-height container, which leaves the answer's space
 * reserved as a blank gap.)
 */
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
  const panelRef = useRef<HTMLDivElement>(null);
  const isFirstRun = useRef(true);

  useEffect(() => {
    const panel = panelRef.current;
    if (!panel) return;

    // An item rendered open on first paint shouldn't animate itself open on page load.
    if (isFirstRun.current) {
      isFirstRun.current = false;
      panel.style.maxHeight = open ? "none" : "0px";
      return;
    }

    if (open) {
      panel.style.maxHeight = `${panel.scrollHeight}px`;
      // Slightly longer than the 0.35s transition in marketing.css. A timer rather than a
      // transitionend listener, because that event never fires under prefers-reduced-motion,
      // which would leave the panel pinned to its measured height forever.
      const release = setTimeout(() => {
        panel.style.maxHeight = "none";
      }, 400);
      return () => clearTimeout(release);
    }

    // Collapsing: pin the current height first, so there's a concrete value to animate from
    // (it's `none` by the time an open panel gets closed).
    panel.style.maxHeight = `${panel.scrollHeight}px`;
    const collapse = requestAnimationFrame(() => {
      panel.style.maxHeight = "0px";
    });
    return () => cancelAnimationFrame(collapse);
  }, [open]);

  return (
    <div className={`acc-item${open ? " open" : ""}`}>
      <button type="button" className="acc-q" onClick={() => setOpen((v) => !v)} aria-expanded={open}>
        {question}
        <svg className="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
          <path d="M6 9l6 6 6-6" />
        </svg>
      </button>
      <div className="acc-a" ref={panelRef}>
        <p>{answer}</p>
      </div>
    </div>
  );
}
