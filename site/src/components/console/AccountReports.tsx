import Link from "next/link";
import { Flag, ShieldOff } from "lucide-react";
import { StatusPill } from "@/components/site/StatusPill";
import type { ReportAboutAccount } from "@/lib/console/accountDetail";
import { shortDate, shortDateTime } from "@/lib/console/format";
import { AccountCard } from "@/components/console/AccountLayout";

/** How many reports open with their message showing. Past this they start folded, so an account
 *  with a long history is a list to scan rather than a wall of other people's words. */
const OPEN_BY_DEFAULT = 3;

/**
 * Every abuse report naming this account: when, who sent it, from where, and what they wrote.
 *
 * Read from `admin_reports_about` (site migration 20261113001300), which only answers a support
 * admin. Reports and block notices are counted apart: a block notice is the app telling support that
 * somebody used the block button, not somebody reporting anyone, and blocks already have their own
 * card beside this one.
 *
 * The reporter is a link to their own account, so "who is this person and are they credible" is one
 * click. A reporter who has since deleted their account still shows, by the address they reported
 * under, because support_requests is never scrubbed.
 */
export function AccountReports({ reports, loadFailed }: { reports: ReportAboutAccount[]; loadFailed?: boolean }) {
  const realReports = reports.filter((r) => !r.is_block_notice);
  const blockNotices = reports.length - realReports.length;
  const reporters = new Set(realReports.map((r) => r.reporter_id ?? r.reporter_email ?? r.request_id)).size;
  const open = realReports.filter((r) => r.thread_status === "open").length;

  return (
    <AccountCard
      title="Reports"
      action={
        !loadFailed && realReports.length > 0 ? (
          <StatusPill tone="error" icon={<Flag />}>
            {realReports.length} {realReports.length === 1 ? "report" : "reports"}
          </StatusPill>
        ) : undefined
      }
      description={
        loadFailed
          ? "Reports didn't load. Refresh to try again."
          : summary(realReports.length, reporters, open, blockNotices)
      }
    >
      {!loadFailed && reports.length > 0 && (
        <ul className="account-reports">
          {reports.map((report, i) => (
            <ReportItem
              key={report.request_id}
              report={report}
              defaultOpen={i < OPEN_BY_DEFAULT && !report.is_block_notice}
            />
          ))}
        </ul>
      )}
      {!loadFailed && reports.length >= 500 && <p className="account-hint">Showing the newest 500.</p>}
    </AccountCard>
  );
}

function summary(count: number, reporters: number, open: number, blockNotices: number): string {
  const notices =
    blockNotices > 0 ? ` ${blockNotices} block ${blockNotices === 1 ? "notice" : "notices"} listed too.` : "";
  if (count === 0) return `Nobody has reported this account.${notices}`;
  const times = `By ${reporters} ${reporters === 1 ? "person" : "people"}`;
  const stillOpen = open > 0 ? `, ${open} still open` : "";
  return `${times}${stillOpen}.${notices}`;
}

function ReportItem({ report, defaultOpen }: { report: ReportAboutAccount; defaultOpen: boolean }) {
  return (
    <li className="account-report">
      <div className="account-report-line">
        {report.is_block_notice ? (
          <StatusPill tone="warning" icon={<ShieldOff />}>
            Block notice
          </StatusPill>
        ) : (
          <StatusPill tone="error" icon={<Flag />}>
            Report
          </StatusPill>
        )}
        <span className="font-semibold">{shortDateTime(report.created_at)}</span>
        {report.report_surface && <span className="muted">{surfaceLabel(report.report_surface)}</span>}
        <span className="account-report-status">
          <ThreadStatus report={report} />
        </span>
      </div>

      <p className="account-report-by">
        {report.is_block_notice ? "Blocked by " : "By "}
        <Reporter report={report} />
      </p>

      <details open={defaultOpen}>
        <summary>{report.is_block_notice ? "Notice" : "What they wrote"}</summary>
        <div className="account-report-quote">
          {report.subject && !report.is_block_notice && <strong>{report.subject}</strong>}
          {report.message}
        </div>
      </details>

      {(report.thread_handler_note || report.thread_id) && (
        <div className="account-report-foot">
          {report.thread_handler_note && (
            <span>
              <b>Internal note:</b> {report.thread_handler_note}
            </span>
          )}
          {report.thread_id && (
            <Link href={`/admin/support?status=all&thread=${report.thread_id}`} className="account-card-link">
              Open the conversation
            </Link>
          )}
        </div>
      )}
    </li>
  );
}

function Reporter({ report }: { report: ReportAboutAccount }) {
  if (!report.reporter_id) return <span>an unknown sender</span>;

  const name = report.reporter_first_name?.trim();
  return (
    <>
      <Link href={`/admin/users/${report.reporter_id}`}>{name || "no name"}</Link>
      {report.reporter_email && <span> ({report.reporter_email})</span>}
      {report.reporter_deleted_at && <span> · deleted {shortDate(report.reporter_deleted_at)}</span>}
    </>
  );
}

function ThreadStatus({ report }: { report: ReportAboutAccount }) {
  if (report.thread_status === "open") return <StatusPill tone="accent">Open</StatusPill>;
  if (report.thread_status === "closed") {
    return (
      <span className="text-xs text-muted-foreground">
        Closed{report.thread_handled_at ? ` ${shortDate(report.thread_handled_at)}` : ""}
      </span>
    );
  }
  return null;
}

/** Where the reporter reached them, from the app's surface values. */
function surfaceLabel(surface: string): string {
  if (surface === "partner") return "the reporter's partner";
  if (surface === "connection request") return "via a connection request";
  return `via ${surface}`;
}
