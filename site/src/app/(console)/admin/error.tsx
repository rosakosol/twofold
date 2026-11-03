"use client";

import { useEffect } from "react";
import { ConsoleError, ConsolePageHead } from "@/components/console/ConsoleUI";

/**
 * Any console page that throws, a failed read above all (lib/console/readResult.ts), lands here,
 * inside the console's header rather than on Next's bare error page. It sits below the (console)
 * layout, so it can't catch the layout's own sign-in and role gate, which is what keeps the header
 * on screen.
 *
 * In production a server component's message is replaced by a digest, which is what to search the
 * Vercel logs for, so that is what is shown.
 */
export default function ConsoleErrorPage({
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
    <div>
      <ConsolePageHead title="Something went wrong" />
      <ConsoleError title="This page didn't load" onRetry={() => retry()}>
        A read failed, so nothing on this page can be trusted to be empty or up to date.
        {error.digest && (
          <>
            {" "}
            Reference <code>{error.digest}</code> in the server logs.
          </>
        )}
      </ConsoleError>
    </div>
  );
}
