import { redirect } from "next/navigation";
import "@/styles/site-nav.css";
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
 * `isConsoleAdmin` fails closed and redirects to the public board rather than to sign-in: a
 * signed-out visitor and a signed-in non-admin should both land somewhere real instead of being
 * told an admin area exists.
 */
export default async function ConsoleLayout({ children }: { children: React.ReactNode }) {
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
