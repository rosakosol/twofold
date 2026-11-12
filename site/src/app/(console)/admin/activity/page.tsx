import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { ConsoleEmpty, ConsolePageHead } from "@/components/console/ConsoleUI";
import { shortDateTime } from "@/lib/console/format";
import { dataOrThrow, listOrThrow } from "@/lib/db/readResult";
import { nullableArg } from "@/lib/db/nullableArg";

export const metadata: Metadata = { title: "Activity" };
export const dynamic = "force-dynamic";

const LIMIT = 300;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface Entry {
  actor_id: string;
  actor_email: string | null;
  action: string;
  subject_profile_id: string | null;
  subject_email: string | null;
  reason: string | null;
  details: Record<string, unknown> | null;
  occurred_at: string;
}

/**
 * Everything admins have done and read, newest first, from `admin_audit_recent`
 * (20261124000700). Per account history is on each account's page; this is the other direction:
 * what one admin did, including the bulk reads (`read.*`) that name no account.
 */
export default async function ActivityPage({ searchParams }: { searchParams: Promise<{ actor?: string }> }) {
  const { actor } = await searchParams;
  const actorId = actor && UUID.test(actor) ? actor : null;
  const supabase = await createClient();

  const [roleResult, logResult] = await Promise.all([
    supabase.rpc("is_support_admin"),
    supabase.rpc("admin_audit_recent", { p_actor: nullableArg(actorId), p_limit: LIMIT }),
  ]);
  if (dataOrThrow(roleResult, "your console role") !== true) redirect("/admin?denied=support");
  const entries = listOrThrow(logResult, "the admin log") as Entry[];
  const actorEmail = actorId ? (entries[0]?.actor_email ?? actorId) : null;

  return (
    <div className="account-page">
      <ConsolePageHead
        title="Activity"
        description={
          actorEmail ? (
            <>
              What {actorEmail} has done and read. <Link href="/admin/activity">Show every admin</Link>
            </>
          ) : (
            "What every admin has done and read, newest first. The log is append-only."
          )
        }
      />
      {entries.length === 0 ? (
        <ConsoleEmpty title="Nothing recorded yet." />
      ) : (
        <div className="console-table-wrap">
          <table className="console-table">
            <thead>
              <tr>
                <th scope="col">When</th>
                <th scope="col">By</th>
                <th scope="col">Action</th>
                <th scope="col">Account</th>
              </tr>
            </thead>
            <tbody>
              {entries.map((entry, i) => (
                <tr key={i}>
                  <td className="muted" style={{ whiteSpace: "nowrap" }}>
                    {shortDateTime(entry.occurred_at)}
                  </td>
                  <td className="account-history-by">
                    <Link href={`/admin/activity?actor=${entry.actor_id}`}>{entry.actor_email ?? entry.actor_id}</Link>
                  </td>
                  <td>
                    <span className="console-mono">{entry.action}</span>
                    {entry.details && <p className="account-history-reason console-mono">{summarise(entry.details)}</p>}
                    {entry.reason && <p className="account-history-reason">{entry.reason}</p>}
                  </td>
                  <td>
                    {entry.subject_profile_id ? (
                      <Link href={`/admin/users/${entry.subject_profile_id}`}>
                        {entry.subject_email ?? entry.subject_profile_id}
                      </Link>
                    ) : (
                      <span className="muted">-</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {entries.length >= LIMIT && <p className="account-empty-line">The newest {LIMIT} are shown.</p>}
    </div>
  );
}

/** `rows 100, offset 200`: the counts and ids a row was logged with, never content. */
function summarise(details: Record<string, unknown>): string {
  return Object.entries(details)
    .map(([key, value]) => `${key} ${typeof value === "object" ? JSON.stringify(value) : String(value)}`)
    .join(", ");
}
