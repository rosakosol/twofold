import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { AccountDetailView } from "@/components/console/AccountDetailView";
import type { CoupleArchive } from "@/components/console/AccountArchives";
import type { FlightOverride } from "@/components/console/AccountGrants";
import { dataOrThrow, isNotFoundError, listOrThrow } from "@/lib/console/readResult";
import type { AccountDetail, AuditEntry, ReportAboutAccount } from "@/lib/console/accountDetail";

export const metadata: Metadata = { title: "Account" };
export const dynamic = "force-dynamic";

/** How much admin history loads. The view shows ten and says when there may be more than this. */
const AUDIT_LIMIT = 20;

/**
 * One account, read-only.
 *
 * Every field here is status or structure. No memories, no photos, no answers, no documents, and
 * no flight rows - flights are counts, because `flights.shared = false` means "my partner cannot
 * see this flight", the privacy policy promises that by name, and the people who use that switch
 * include people leaving a relationship that is not safe. A count answers every support question a
 * list would.
 *
 * Loading this page writes an audit row. That is deliberate and it is the reason the reason field
 * exists on the RPC: this is the call that turns an email address into a person.
 */
export default async function AccountDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  // All six at once. Each is a round trip to Sydney, and run one after another they were the
  // reason this page felt like a dead link - four sequential waits before anything rendered.
  //
  // The gate is among them rather than in front of them. Every one of these RPCs checks
  // is_support_admin() in its own body and raises 42501 otherwise, so a non-admin firing the other
  // five costs five refusals and learns nothing; the alternative is making every legitimate load
  // wait for a permission check whose answer is almost always yes.
  const [roleResult, detailResult, auditResult, overrideResult, archivesResult, reportsResult] = await Promise.all([
    supabase.rpc("is_support_admin"),
    supabase.rpc("admin_account_detail", { p_profile_id: id }),
    supabase.rpc("admin_audit_for_subject", { p_profile_id: id, p_limit: AUDIT_LIMIT }),
    supabase.rpc("admin_flight_limit_override", { p_profile_id: id }),
    supabase.rpc("admin_couple_archives", { p_profile_id: id }),
    supabase.rpc("admin_reports_about", { p_profile_id: id }),
  ]);

  if (dataOrThrow(roleResult, "your console role") !== true) redirect("/admin");
  // "No such account" only when it is one: a null row (unknown id) or a malformed id. A refusal or
  // an outage used to land here too, telling the operator an account they could see a moment ago
  // did not exist.
  if (isNotFoundError(detailResult.error)) notFound();
  const detailData = dataOrThrow(detailResult, "this account");
  if (!detailData) notFound();

  const detail = detailData as unknown as AccountDetail;
  const audit = listOrThrow(auditResult, "this account's history") as AuditEntry[];
  const override = dataOrThrow(overrideResult, "this account's flight limit") as FlightOverride | null;
  const archives = listOrThrow(archivesResult, "this account's archives") as CoupleArchive[];
  // Reports keep their own inline failure state (AccountReports), so they don't take the page down.
  const reports = (reportsResult.data ?? []) as ReportAboutAccount[];

  return (
    <AccountDetailView
      detail={detail}
      audit={audit}
      auditLimit={AUDIT_LIMIT}
      override={override}
      archives={archives}
      reports={reports}
      reportsFailed={Boolean(reportsResult.error)}
    />
  );
}
