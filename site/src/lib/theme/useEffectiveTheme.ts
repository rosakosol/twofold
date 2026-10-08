"use client";

import { useSyncExternalStore } from "react";
import { DARK_QUERY, getEffectiveTheme, type Theme } from "@/lib/theme/themeScript";

/** Re-reads on a system change (while no choice is stored) and on any change to data-theme. */
function subscribe(onChange: () => void) {
  const media = window.matchMedia(DARK_QUERY);
  media.addEventListener("change", onChange);
  const observer = new MutationObserver(onChange);
  observer.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
  return () => {
    media.removeEventListener("change", onChange);
    observer.disconnect();
  };
}

/**
 * The theme the page is showing, for the few things that need it in script rather than CSS (the
 * toasts). Anything that can should key on the CSS instead: `.theme-light-only`/`.theme-dark-only`
 * in tokens.css, or the `dark:` variant, which are right before hydration as well.
 *
 * `null` on the server and during hydration, when it cannot be known.
 */
export function useEffectiveTheme(): Theme | null {
  return useSyncExternalStore(subscribe, getEffectiveTheme, () => null);
}
