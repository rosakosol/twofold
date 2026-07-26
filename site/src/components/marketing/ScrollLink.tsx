"use client";

/**
 * An in-page jump that scrolls to a section without leaving a `#hash` behind in the URL.
 *
 * A plain `<a href="#quiz">` writes the fragment into the address bar, and the browser then
 * re-applies it on every subsequent load of that URL — so a visitor who once pressed "Get
 * started" lands part-way down the page, on the quiz, every time they come back or refresh,
 * instead of at the top. Preventing the default navigation and scrolling manually keeps the
 * behaviour without the persistence.
 *
 * The `href` is kept real rather than swapped for a button: it stays keyboard- and
 * right-click-friendly, and if the target is missing (or JS hasn't loaded) the browser's own
 * fragment navigation still does something sensible.
 */
export function ScrollLink({
  targetId,
  className,
  children,
}: {
  targetId: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <a
      href={`#${targetId}`}
      className={className}
      onClick={(event) => {
        const target = document.getElementById(targetId);
        if (!target) return;
        event.preventDefault();
        target.scrollIntoView({ behavior: "smooth", block: "start" });
      }}
    >
      {children}
    </a>
  );
}
