import { headers } from "next/headers";
import { redirect } from "next/navigation";
import "@/styles/site-nav.css";
import "@/styles/console.css";
import { createClient } from "@/lib/supabase/server";
import { ShieldAlert } from "lucide-react";
import Link from "next/link";
import { getConsoleAccess } from "@/lib/auth/consoleAccess";
import { consoleGate } from "@/lib/auth/consoleGate";
import { ConsoleHeader } from "@/components/console/ConsoleHeader";
import type { Metadata } from "next";

// An internal tool: never indexed, whatever a crawler is handed a link to. robots.ts disallows
// /admin as well, but a disallowed URL can still be listed from links; this header can't.
export const metadata: Metadata = {
  title: { default: "Console", template: "%s | Twofold console" },
  robots: { index: false, follow: false },
};

/**
 * The internal console: a separate shell from the public website, not a set of extra links inside
 * it. See ConsoleHeader for why the two are kept apart.
 *
 * A route group, so the URLs do not move — /admin and /admin/games are exactly where they were,
 * and every bookmark and link still works. The only thing that changes is which chrome wraps them.
 *
 * The gate is `my_console_access` — ANY admin role — not `is_feedback_admin`, which since the role
 * split means `content` specifically. Gating the door on one role would lock a billing-only admin
 * out of the console entirely, undoing the separation the roles were created for. Each page inside
 * still checks the role it actually needs.
 *
 * The gate lives here rather than in admin/layout.tsx so that anything added to this group is
 * behind it by default. Getting that the wrong way round means a new console page is public until
 * somebody remembers, and nothing would fail to say so.
 *
 * Two refusals, not one, because they are different situations and used to share an outcome.
 *
 * Somebody with no session is not being refused — they have not asked yet. Sending them to the
 * feedback board meant an admin who typed /admin, or followed a bookmark after their cookie
 * expired, landed on a public page with no explanation and no way back other than typing the URL
 * again. They now get sign-in carrying `next`, so finishing it returns them to the console.
 *
 * Somebody signed in WITHOUT a role has been refused, and the board is the right place for them:
 * it is a real page they can use, and it does not confirm that an admin area exists.
 *
 * An admin at aal1 is a third situation: they still hold the role and have a step left to do, so
 * they go to /admin/mfa (consoleGate says how that behaves before and after the database starts
 * enforcing it). This only routes. What actually refuses them is `is_*_admin()` in the database.
 */
export default async function ConsoleLayout({ children }: { children: React.ReactNode }) {
  // Cheap and already warm — the middleware refreshed this session on the way in.
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) {
    // The path the browser actually asked for, set by the middleware — so a bookmark to
    // /admin/usage comes back to /admin/usage rather than to the console's front door.
    const requested = (await headers()).get("x-pathname") ?? "/admin";
    redirect(`/auth/sign-in?next=${encodeURIComponent(requested)}`);
  }

  const gate = consoleGate(await getConsoleAccess());
  if (gate === "not-admin") redirect("/feedback");
  if (gate === "challenge" || gate === "enrol") {
    const requested = (await headers()).get("x-pathname") ?? "/admin";
    redirect(`/admin/mfa?next=${encodeURIComponent(requested)}`);
  }

  return (
    <div className="board-shell flex min-h-screen flex-1 flex-col">
      <ConsoleHeader />
      <main className="flex-1">
        <div className="console-main">
          {gate === "open-prompt-enrol" && (
            <div className="mfa-banner" role="status">
              <ShieldAlert aria-hidden />
              <p>
                <strong>Your admin account has no second factor.</strong> A stolen password would open this console, and
                it will soon be required.
              </p>
              <Link href="/admin/mfa" className="btn btn-secondary btn-sm">
                Set it up
              </Link>
            </div>
          )}
          {children}
        </div>
      </main>
    </div>
  );
}
