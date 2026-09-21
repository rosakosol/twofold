import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/server";
import { cancellability, type AccountDetail, type AuditEntry } from "@/lib/console/accountDetail";

export const metadata: Metadata = { title: "Account" };
export const dynamic = "force-dynamic";

/**
 * One account, read-only.
 *
 * Every field here is status or structure. No memories, no photos, no answers, no documents, and
 * no flight rows — flights are counts, because `flights.shared = false` means "my partner cannot
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

  const { data: isSupportAdmin } = await supabase.rpc("is_support_admin");
  if (isSupportAdmin !== true) redirect("/admin");

  const { data, error } = await supabase.rpc("admin_account_detail", { p_profile_id: id });
  if (error || !data) notFound();
  const detail = data as unknown as AccountDetail;

  const { data: auditData } = await supabase.rpc("admin_audit_for_subject", {
    p_profile_id: id,
    p_limit: 20,
  });
  const audit = (auditData ?? []) as AuditEntry[];

  const subscription = cancellability(detail.subscription.store, detail.subscription.active);

  return (
    <div className="space-y-6">
      <Link
        href="/admin/users"
        className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
      >
        <ArrowLeft className="h-3.5 w-3.5" />
        Accounts
      </Link>

      <header>
        <h1 className="font-heading text-xl font-semibold tracking-tight">
          {detail.auth.email ?? "no email"}
        </h1>
        <p className="mt-1 flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
          <span>{detail.profile.first_name || "no name"}</span>
          <span>·</span>
          <span>joined {formatDate(detail.profile.created_at)}</span>
          {detail.auth.deleted_at && <Badge variant="destructive">Deleted {formatDate(detail.auth.deleted_at)}</Badge>}
        </p>
      </header>

      {detail.auth.deleted_at && (
        <Card className="border-destructive/40">
          <CardContent className="pt-6 text-sm text-muted-foreground">
            This account was deleted. The row still exists on purpose — <code>delete-account</code>{" "}
            soft-deletes so the foreign-key cascade never fires and takes the other partner&apos;s
            shared history with it. Sign-in is permanently disabled and cannot be restored.
          </CardContent>
        </Card>
      )}

      <div className="grid gap-4 sm:grid-cols-2">
        <Panel title="Subscription">
          <Row label="Status" value={detail.subscription.active ? "Active" : "None"} />
          <Row label="Plan" value={detail.subscription.tier ?? "—"} />
          <Row label="Bought via" value={subscription.label} highlight={!subscription.ours && detail.subscription.active} />
          <Row
            label="Renews"
            value={
              detail.subscription.will_renew === null
                ? "unknown"
                : detail.subscription.will_renew
                  ? "yes"
                  : "no — cancelled"
            }
          />
          <Row label="Since" value={formatDate(detail.subscription.started_at)} />
          <Row label="Last checked" value={formatDate(detail.subscription.checked_at)} />
        </Panel>

        <Panel title="Partner">
          {detail.couple ? (
            <>
              <Row label="Partner" value={detail.couple.partner_first_name ?? "—"} />
              <Row label="Their email" value={detail.couple.partner_email ?? "—"} />
              <Row label="Together since" value={formatDate(detail.couple.started_dating_on)} />
              <Row label="Paired on" value={formatDate(detail.couple.created_at)} />
              <div className="pt-1">
                <Link
                  href={`/admin/users/${detail.couple.partner_id}`}
                  className="text-sm underline underline-offset-4"
                >
                  Open their account
                </Link>
              </div>
            </>
          ) : (
            <p className="text-sm text-muted-foreground">Not currently paired.</p>
          )}
        </Panel>

        <Panel title="Activity">
          <Row label="Last active" value={formatDate(detail.profile.last_active_at)} />
          <Row label="Last sign-in" value={formatDate(detail.auth.last_sign_in_at)} />
          <Row label="Finished onboarding" value={formatDate(detail.profile.onboarding_completed_at)} />
          <Row
            label="Dormancy warned"
            value={formatDate(detail.profile.dormancy_warned_at)}
            highlight={Boolean(detail.profile.dormancy_warned_at)}
          />
          <Row label="Sign-in methods" value={detail.auth.providers.join(", ") || "—"} />
          <Row label="Timezone" value={detail.profile.timezone ?? "—"} />
        </Panel>

        <Panel title="Content">
          {/* Counts only, and the comment beside them is the policy. */}
          <Row label="Flights tracked" value={String(detail.counts.flights_tracked)} />
          <Row label="Still tracking" value={String(detail.counts.flights_tracking_enabled)} />
          <Row label="Trips" value={String(detail.counts.trips)} />
          <Row label="Memories" value={String(detail.counts.memories)} />
          {detail.flight_allowance && (
            <Row
              label="Flight allowance"
              value={`${detail.flight_allowance.used ?? 0} of ${detail.flight_allowance.limit ?? "—"} this month`}
            />
          )}
          <p className="pt-2 text-xs text-muted-foreground">
            Counts only. Flights are never listed here — a hidden flight is hidden from the
            person&apos;s own partner, and a count answers the question a list would.
          </p>
        </Panel>

        <Panel title="Credits">
          <Row label="Streak repairs unused" value={String(detail.credits.streak_repair_unused)} />
          <Row label="Record exports unused" value={String(detail.credits.record_export_unused)} />
        </Panel>

        <Panel title="Blocks">
          <Row label="People they blocked" value={String(detail.counts.blocked_by_them)} />
          <Row
            label="People blocking them"
            value={String(detail.counts.blocking_them)}
            highlight={detail.counts.blocking_them > 0}
          />
        </Panel>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Admin history</CardTitle>
        </CardHeader>
        <CardContent>
          {audit.length === 0 ? (
            <p className="text-sm text-muted-foreground">Nothing recorded.</p>
          ) : (
            <ul className="space-y-2 text-sm">
              {audit.map((entry, i) => (
                <li key={i} className="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
                  <span className="font-mono text-xs">{entry.action}</span>
                  <span className="text-muted-foreground">by {entry.actor_email ?? entry.actor_id}</span>
                  <span className="text-muted-foreground">· {formatDateTime(entry.occurred_at)}</span>
                  {entry.reason && <span className="w-full text-xs text-muted-foreground">{entry.reason}</span>}
                </li>
              ))}
            </ul>
          )}
          <p className="mt-3 text-xs text-muted-foreground">
            Opening this page is itself recorded. The log is append-only and has no delete path.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base">{title}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-1.5">{children}</CardContent>
    </Card>
  );
}

function Row({ label, value, highlight }: { label: string; value: string; highlight?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-4 text-sm">
      <span className="shrink-0 text-muted-foreground">{label}</span>
      <span className={`truncate text-right ${highlight ? "font-medium text-destructive" : ""}`}>{value}</span>
    </div>
  );
}

function formatDate(value: string | null): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}

function formatDateTime(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}
