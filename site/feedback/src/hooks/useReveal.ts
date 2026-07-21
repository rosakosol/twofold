"use client";

import { useEffect, useRef } from "react";

/** Per-element port of site/assets/js/site.js's global reveal-on-scroll — adds
 * "is-visible" once the element crosses the same threshold/rootMargin the old
 * IntersectionObserver used, then stops observing (matches the original's
 * one-shot behavior). Falls back to immediately visible if IntersectionObserver
 * isn't available, same as the original. Attach the returned ref to any element
 * with className="reveal" (see marketing.css for the transition itself). */
export function useReveal<T extends HTMLElement>() {
  const ref = useRef<T>(null);

  useEffect(() => {
    const node = ref.current;
    if (!node) return;

    if (!("IntersectionObserver" in window)) {
      node.classList.add("is-visible");
      return;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            node.classList.add("is-visible");
            observer.unobserve(node);
          }
        }
      },
      { threshold: 0.12 }
    );
    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  return ref;
}
