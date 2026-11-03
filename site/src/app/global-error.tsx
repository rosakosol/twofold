"use client";

import "./globals.css";

/**
 * The last resort: an error in the root layout itself. It replaces that layout, so it brings its
 * own <html> and <body>, and the stored light/dark choice isn't applied (tokens.css still follows
 * the system setting).
 */
export default function GlobalError({
  error,
  retry,
}: {
  error: Error & { digest?: string };
  retry: () => void;
}) {
  return (
    <html lang="en">
      <body className="antialiased min-h-screen flex flex-col">
        <title>Something went wrong | Twofold</title>
        <main className="flex flex-1 flex-col items-center justify-center gap-4 px-6 py-24 text-center">
          <h1 className="board-page-title">Something went wrong</h1>
          <p className="max-w-md text-muted-foreground">
            Twofold&apos;s website hit an error. Trying again usually fixes it.
            {error.digest && <> Reference: {error.digest}</>}
          </p>
          <button type="button" className="btn btn-primary" onClick={() => retry()}>
            Try again
          </button>
        </main>
      </body>
    </html>
  );
}
