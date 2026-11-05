import { redirect } from "next/navigation";
import "@/styles/site-nav.css";
import "@/styles/console.css";
import { getCurrentUser } from "@/lib/auth/server";
import { ConsoleHeader } from "@/components/console/ConsoleHeader";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: { default: "Console", template: "%s | Twofold console" },
  robots: { index: false, follow: false },
};

/**
 * The console's chrome for the one page that has to work at aal1, where the (console) layout's gate
 * would send it straight back here. A sibling route group rather than an exception inside that gate:
 * a gate with a hole in it is what "new pages are behind it by default" exists to avoid.
 *
 * It can't be done by having the (console) layout render the form in place of `children` either.
 * Next renders the page regardless of whether its layout uses `children`, so the page's data reads
 * and its own redirects would still run.
 */
export default async function ConsoleMfaLayout({ children }: { children: React.ReactNode }) {
  const user = await getCurrentUser();
  if (!user) redirect(`/auth/sign-in?next=${encodeURIComponent("/admin")}`);

  return (
    <div className="board-shell flex min-h-screen flex-1 flex-col">
      <ConsoleHeader showLinks={false} />
      <main className="flex-1">
        <div className="console-main">{children}</div>
      </main>
    </div>
  );
}
