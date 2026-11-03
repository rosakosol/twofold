"use client";

import { useEffect } from "react";
import Link from "next/link";
import "./account.css";

/**
 * The account page couldn't read something it needs. Said plainly rather than guessed at: the page
 * is where people check what they are paying for, so a missing read must not render as "no
 * subscription" or "no partner".
 */
export default function AccountError({
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
    <div className="account-page">
      <h1 className="board-page-title">Your account didn&apos;t load</h1>
      <p className="mt-3 text-muted-foreground">
        We couldn&apos;t read some of your account just now, so we&apos;re not showing a page that might be
        wrong about your subscription or partner. Trying again usually fixes it.
      </p>
      <div className="mt-6 flex flex-wrap gap-3">
        <button type="button" className="btn btn-primary" onClick={() => retry()}>
          Try again
        </button>
        <Link href="/support" className="btn btn-secondary">
          Contact support
        </Link>
      </div>
    </div>
  );
}
