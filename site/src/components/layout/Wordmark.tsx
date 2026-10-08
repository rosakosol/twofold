/**
 * The "twofold" wordmark, set in Newsreader (loaded by next/font in app/layout.tsx as
 * --font-wordmark), regular, at the size and colour of its parent.
 *
 * The app sets it in New York (`.system(design: .serif)`, TwofoldBrandMark.swift), which can't
 * come to the web: Apple's licence covers mock-ups, not embedding or serving it, and leaving it to
 * the system font meant Georgia off Apple devices. Newsreader is the closest open-licence face, so
 * every visitor sees the same word, rendered as real text. The email PNGs in
 * public/assets/wordmark-email-*@3x.png are this same face.
 */
export function Wordmark({ className }: { className?: string }) {
  return (
    <span
      className={className}
      style={{ fontFamily: "var(--font-wordmark), Georgia, serif", fontWeight: 400 }}
      aria-hidden
    >
      twofold
    </span>
  );
}
