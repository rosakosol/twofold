"use client";

import { useEffect } from "react";
import Link from "next/link";

/** A marketing page that threw, inside the site's own header and footer, with a way back. */
export default function MarketingError({
  error,
  retry,
}: {
  error: Error & { digest?: string };
  retry: () => void;
}) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <section style={{ textAlign: "center" }}>
      <div className="wrap-narrow">
        <h1>This page didn&apos;t load</h1>
        <p className="lede" style={{ margin: "0 auto 24px" }}>
          Something went wrong on our side. Trying again usually fixes it.
        </p>
        <div style={{ display: "flex", gap: 12, justifyContent: "center", flexWrap: "wrap" }}>
          <button type="button" className="btn btn-primary btn-lg" onClick={() => retry()}>
            Try again
          </button>
          <Link href="/" className="btn btn-secondary btn-lg">
            Go home
          </Link>
        </div>
      </div>
    </section>
  );
}
