"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { ShieldAlert } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

interface ReportContext {
  reported_profile_id: string;
  report_surface: string | null;
  first_name: string | null;
  email: string | null;
  joined_at: string | null;
  account_deleted_at: string | null;
  times_reported: number;
  distinct_reporters: number;
  blocked_by_count: number;
  reporter_blocked_them: boolean;
  are_partners: boolean;
  were_partners: boolean;
}

/**
 * Who an abuse report is about, beside the report itself.
 *
 * The reporter's message alone said nothing about the person: the app attached their id, but only
 * to the email, which the console does not read. This reads it from the request (20261113001100)
 * and adds the facts that decide what to do, then says what to do, so an abuse report is not
 * handled from memory.
 *
 * Opening it is recorded against the reported account, as opening an account is.
 */
export function ReportedAccountPanel({ requestId }: { requestId: string }) {
  const [context, setContext] = useState<ReportContext | null | undefined>(undefined);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("admin_report_context", { p_request_id: requestId });
      if (cancelled) return;
      setContext(error ? null : ((data as ReportContext[] | null)?.[0] ?? null));
    })();
    return () => {
      cancelled = true;
    };
  }, [requestId]);

  if (context === undefined) return null;

  return (
    <section className="rounded-lg border border-destructive/40 bg-destructive/5 p-3 text-sm">
      <h3 className="flex items-center gap-1.5 font-medium">
        <ShieldAlert className="h-4 w-4 text-destructive" aria-hidden />
        Reported account
      </h3>

      {context === null ? (
        <p className="mt-1 text-xs text-muted-foreground">
          This report doesn&apos;t name an account. It was sent before reports carried one, or from
          somewhere that couldn&apos;t attach it. The reporter&apos;s message is all there is.
        </p>
      ) : (
        <>
          <dl className="mt-2 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
            <dt className="text-muted-foreground">Name</dt>
            <dd>{context.first_name || "no name"}</dd>
            <dt className="text-muted-foreground">Email</dt>
            <dd className="truncate">{context.email ?? "no email"}</dd>
            <dt className="text-muted-foreground">Account</dt>
            <dd>
              {context.account_deleted_at
                ? `Deleted ${formatDate(context.account_deleted_at)}`
                : `Active, joined ${formatDate(context.joined_at)}`}
              {" · "}
              <Link href={`/admin/users/${context.reported_profile_id}`} className="underline underline-offset-2">
                Open account
              </Link>
            </dd>
            <dt className="text-muted-foreground">Relationship</dt>
            <dd>
              {context.are_partners
                ? "The reporter's current partner"
                : context.were_partners
                  ? "The reporter's former partner"
                  : "Not the reporter's partner"}
              {context.report_surface ? `, reported from ${context.report_surface}` : ""}
            </dd>
            <dt className="text-muted-foreground">Reports</dt>
            <dd className={context.distinct_reporters > 1 ? "font-medium text-destructive" : undefined}>
              {context.times_reported} {context.times_reported === 1 ? "report" : "reports"} from{" "}
              {context.distinct_reporters} {context.distinct_reporters === 1 ? "person" : "people"}
            </dd>
            <dt className="text-muted-foreground">Blocks</dt>
            <dd>
              {context.reporter_blocked_them ? "The reporter has blocked them" : "The reporter hasn't blocked them"}
              {`; blocked by ${context.blocked_by_count} ${context.blocked_by_count === 1 ? "person" : "people"} in all`}
            </dd>
          </dl>

          <details className="mt-3" open>
            <summary className="cursor-pointer text-xs font-medium">What to do</summary>
            <ol className="mt-1.5 list-decimal space-y-1 pl-4 text-xs text-muted-foreground">
              <li>
                Reply to the reporter within 48 hours, which is what the app promises. The
                &quot;Abuse report received&quot; saved reply covers it.
              </li>
              <li>
                If anyone may be in danger, tell the reporter to contact emergency services (000 in
                Australia). Twofold can stop contact through the app, nothing more.
              </li>
              {!context.reporter_blocked_them && (
                <li>Suggest they block this person in Settings, which stops all contact through Twofold at once.</li>
              )}
              {context.are_partners && (
                <li>
                  They&apos;re still connected. Offer to disconnect them: open the reporter&apos;s account
                  and use Disconnect, which archives their shared history rather than deleting it.
                </li>
              )}
              <li>
                Delete the reported account (Open account → Delete this account) if the report is
                credible: threats, harassment, sexual content sent without consent, or reports from
                more than one person. Put this report in the reason.
              </li>
              <li>
                Send the &quot;Abuse report: action taken&quot; reply, without details about the other
                person. Write what you did in the internal note below, then close the conversation.
              </li>
            </ol>
          </details>
        </>
      )}
    </section>
  );
}

function formatDate(value: string | null): string {
  if (!value) return "unknown";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "unknown";
  return date.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}
