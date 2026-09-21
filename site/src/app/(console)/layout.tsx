import { headers } from "next/headers";
import { redirect } from "next/navigation";
import "@/styles/site-nav.css";
import { createClient } from "@/lib/supabase/server";
import { isConsoleAdmin } from "@/lib/auth/isConsoleAdmin";
import { ConsoleHeader } from "@/components/console/ConsoleHeader";

/**
 * The internal console: a separate shell from the public website, not a set of extra links inside
 * it. See ConsoleHeader for why the two are kept apart.
 *
 * A route group, so the URLs do not move — /admin and /admin/games are exactly where they were,
 * and every bookmark and link still works. The only thing that changes is which chrome wraps them.
 *
 * The gate is `is_console_admin` — ANY admin role — not `is_feedback_admin`, which since the role
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

  const isAdmin = await isConsoleAdmin();
  if (!isAdmin) redirect("/feedback");

  return (
    <div className="board-shell flex min-h-screen flex-1 flex-col">
      <ConsoleHeader />
      <main className="flex-1">
        <div className="mx-auto max-w-6xl px-4 py-6">{children}</div>
      </main>
    </div>
  );
}
