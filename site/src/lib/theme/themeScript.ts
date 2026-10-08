/**
 * The visitor's light/dark choice, and the one mechanism that applies it.
 *
 * With no choice stored, nothing is set and the site follows the system (tokens.css). A choice,
 * made with ThemeToggle, is `data-theme="light"|"dark"` on <html>, which tokens.css and the `dark`
 * variant in globals.css both already obey, kept in localStorage under THEME_STORAGE_KEY.
 *
 * Deliberately not next-themes: it renders its script from a client component, which React 19
 * warns about on every page, and everything it would manage here is one attribute.
 */

export type Theme = "light" | "dark";

export const THEME_STORAGE_KEY = "twofold-theme";

/**
 * Runs in <head> before the body is parsed (app/layout.tsx), so a stored choice is on <html>
 * before first paint and the page never flashes the system's theme first. Plain ES5 and wrapped in
 * try/catch: storage throws in some private modes and with site data blocked, and then the page
 * simply follows the system. Inline scripts are allowed by the CSP in next.config.ts.
 */
export const THEME_INIT_SCRIPT = `try{var t=localStorage.getItem(${JSON.stringify(THEME_STORAGE_KEY)});if(t==="light"||t==="dark")document.documentElement.setAttribute("data-theme",t)}catch(e){}`;

export const DARK_QUERY = "(prefers-color-scheme: dark)";

/** The theme the page is actually showing: the explicit choice, or else the system's. */
export function getEffectiveTheme(): Theme {
  const set = document.documentElement.getAttribute("data-theme");
  if (set === "light" || set === "dark") return set;
  return window.matchMedia(DARK_QUERY).matches ? "dark" : "light";
}

/** Applies and remembers an explicit choice. Once made, it sticks over the system. */
export function setTheme(theme: Theme) {
  document.documentElement.setAttribute("data-theme", theme);
  try {
    localStorage.setItem(THEME_STORAGE_KEY, theme);
  } catch {
    // Storage unavailable: the choice holds for this page view only.
  }
}
