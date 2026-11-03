import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = { title: "Page not found", robots: { index: false } };

/**
 * Any URL that matches no route. Rendered inside the root layout only, which deliberately has no
 * header or footer (each route group brings its own), so this carries its own way out.
 */
export default function NotFound() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center gap-4 px-6 py-24 text-center">
      <p className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">404</p>
      <h1 className="board-page-title">We couldn&apos;t find that page</h1>
      <p className="max-w-md text-muted-foreground">
        The link may be mistyped, or the page has moved.
      </p>
      <div className="mt-2 flex flex-wrap justify-center gap-3">
        <Link href="/" className="btn btn-primary">
          Go home
        </Link>
        <Link href="/support" className="btn btn-secondary">
          Contact support
        </Link>
      </div>
    </main>
  );
}
