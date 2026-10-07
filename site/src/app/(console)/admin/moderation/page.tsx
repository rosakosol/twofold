import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { CheckCircle2 } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { ConsoleEmpty, ConsolePageHead, StatTiles } from "@/components/console/ConsoleUI";
import { StatusPill } from "@/components/site/StatusPill";

export const metadata: Metadata = { title: "Moderation" };
export const dynamic = "force-dynamic";

interface MostBlocked {
  profile_id: string;
  email: string | null;
  first_name: string;
  blocked_by_count: number;
  most_recent: string;
}

/**
 * Accounts that several unrelated people have blocked.
 *
 * Deliberately a ranking with a floor of two, not a browsable list of every block. One block is a
 * falling-out; several from unrelated people is the thing that turns one person's abuse report
 * into something with corroboration. A list of who blocked whom would be a graph of interpersonal
 * dislike across the whole app, answering no support question and sitting somewhere it could be
 * read for no reason.
 *
 * Blocking is invisible to the blocked party in the app — DisconnectPartnerView says "They aren't
 * told" — and nothing here changes that. This page is for looking into a report that has already
 * arrived, not for acting on people who have no idea they are on a list.
 */
export default async function ModerationPage() {
  const supabase = await createClient();

  // Same as every other console page: the read enforces the role itself, so the check rides
  // alongside it rather than in front of it.
  const [{ data: isSupportAdmin }, { data }, { data: openRequests }] = await Promise.all([
    supabase.rpc("is_support_admin"),
    supabase.rpc("admin_most_blocked", { p_min_blocks: 2, p_limit: 50 }),
    // The same read the Support page makes, for the count of open abuse reports.
    supabase.rpc("admin_support_requests", { p_status: "open", p_limit: 200 }),
  ]);

  if (isSupportAdmin !== true) redirect("/admin");
  const rows = (data ?? []) as MostBlocked[];
  const openReports = new Set(
    ((openRequests ?? []) as { thread_id: string; category: string }[])
      .filter((r) => r.category === "Report Abuse")
      .map((r) => r.thread_id),
  ).size;

  return (
    <div>
      <ConsolePageHead title="Moderation" description="Accounts blocked by more than one person, and where abuse reports go." />

      <StatTiles
        items={[
          { label: "Repeatedly blocked", value: rows.length, hint: "Blocked by two or more people" },
          { label: "Open abuse reports", value: openReports, hint: "In the Support inbox" },
          { label: "Response promise", value: "48 hours", hint: "What the app tells a reporter" },
        ]}
      />

      <div className="moderation-cards">
        <section className="console-card console-card-pad" aria-labelledby="blocked-title">
          <h2 id="blocked-title">Repeatedly blocked</h2>
          <p className="console-card-sub">A single block is usually a break-up. Two or more unrelated ones is worth a look.</p>
          {rows.length === 0 ? (
            <ConsoleEmpty title="Nobody has been blocked by more than one person" tone="success">
              <span className="inline-flex items-center gap-1.5">
                <CheckCircle2 className="h-4 w-4" aria-hidden />
                That is the expected state.
              </span>
            </ConsoleEmpty>
          ) : (
            <ul className="console-list">
              {rows.map((row) => (
                <li key={row.profile_id}>
                  <Link href={`/admin/users/${row.profile_id}`} className="console-list-row">
                    <span className="min-w-0">
                      <span className="console-row-link block truncate">{row.email ?? "No email"}</span>
                      <span className="block truncate muted">
                        {row.first_name || "No name"}, most recent{" "}
                        {new Date(row.most_recent).toLocaleDateString("en-AU", { day: "numeric", month: "long", year: "numeric" })}
                      </span>
                    </span>
                    <StatusPill tone={row.blocked_by_count >= 3 ? "error" : "warning"}>Blocked by {row.blocked_by_count}</StatusPill>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="console-card console-card-pad" aria-labelledby="reports-title">
          <h2 id="reports-title">Abuse reports</h2>
          <div className="console-card-prose">
            <p>
              Reports arrive as support requests under the <strong>Report abuse</strong> category and are listed in Support,
              where they are marked so they are not skimmed past.
            </p>
            <p>
              They are still emailed to support@ as well. That is what actually notifies anybody, and it is what the app&apos;s
              48-hour promise has always rested on. The queue is the record beside it, so &ldquo;was this answered&rdquo; has an
              answer.
            </p>
          </div>
          <Link className="btn btn-secondary btn-sm" href="/admin/support?status=open">
            Open abuse reports in Support
          </Link>
        </section>
      </div>
    </div>
  );
}
