"use client";

import { Moon, Sun } from "lucide-react";
import { getEffectiveTheme, setTheme } from "@/lib/theme/themeScript";

function toggleTheme() {
  setTheme(getEffectiveTheme() === "dark" ? "light" : "dark");
}

/**
 * Light/dark, in SiteHeader and ConsoleHeader. Until it is pressed the site follows the system;
 * after that the choice sticks (lib/theme/themeScript.ts).
 *
 * Two forms, as with Sign in: a 44px round button in the bar on a wide screen, and a row in the
 * folded menu on a phone, where the bar has room for Download and the menu button and nothing
 * else. site-nav.css shows the one that fits.
 *
 * Both icons and both labels are rendered and `.theme-*-only` (tokens.css) picks one, so they are
 * right from the first paint, before hydration, and follow a system change by themselves. Hidden
 * content is left out of the accessible name, so the button is announced with the label that
 * applies.
 */
export function ThemeToggle({ variant = "button" }: { variant?: "button" | "menu-row" }) {
  if (variant === "menu-row") {
    return (
      <li className="site-nav-theme-row">
        <button type="button" onClick={toggleTheme}>
          <Moon aria-hidden className="theme-light-only" />
          <Sun aria-hidden className="theme-dark-only" />
          <span className="theme-light-only">Switch to dark mode</span>
          <span className="theme-dark-only">Switch to light mode</span>
        </button>
      </li>
    );
  }

  return (
    <button type="button" className="site-nav-theme" onClick={toggleTheme}>
      <Moon aria-hidden className="theme-light-only" />
      <Sun aria-hidden className="theme-dark-only" />
      <span className="sr-only theme-light-only">Switch to dark mode</span>
      <span className="sr-only theme-dark-only">Switch to light mode</span>
    </button>
  );
}
