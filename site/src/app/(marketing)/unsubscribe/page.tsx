import type { Metadata } from "next";
import { Suspense } from "react";
import "./unsubscribe.css";
import { UnsubscribeClient } from "@/components/marketing/UnsubscribeClient";

export const metadata: Metadata = {
  title: "Email preferences",
  robots: { index: false },
};

/** Where an email's unsubscribe link lands. It asks before changing anything, so a mail scanner
 *  that opens the link unsubscribes nobody. The link's token is the only credential. */
export default function UnsubscribePage() {
  return (
    <section className="unsub" aria-labelledby="unsub-title">
      <div className="page-wrap">
        <Suspense>
          <UnsubscribeClient />
        </Suspense>
      </div>
    </section>
  );
}
