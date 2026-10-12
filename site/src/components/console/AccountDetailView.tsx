import Link from "next/link";
import { ArrowLeft, ArrowRight, Flag, Heart, LayoutGrid, ShieldAlert, ShieldOff, Trash2 } from "lucide-react";
import { StatusPill } from "@/components/site/StatusPill";
import { AccountActions } from "@/components/console/AccountActions";
import { AccountGrants, type FlightOverride } from "@/components/console/AccountGrants";
import { AccountArchives, type CoupleArchive } from "@/components/console/AccountArchives";
import { AccountReports } from "@/components/console/AccountReports";
import { AccountHistory } from "@/components/console/AccountHistory";
import { AccountCard, AccountSection, Fact, Facts } from "@/components/console/AccountLayout";
import { InfoTip } from "@/components/console/InfoTip";
import {
  cancellability,
  type AccountDetail,
  type AuditEntry,
  type ReportAboutAccount,
} from "@/lib/console/accountDetail";
import { daysAgo, shortDate } from "@/lib/console/format";

/**
 * One account, laid out: who it is and the gist in the header, then Overview, Safety, Grants,
 * the danger zone and the admin history as sections with their own headings and in-page links.
 *
 * Takes what the page fetched and fetches nothing, so the page owns every RPC (and the audit row
 * loading it writes) and this owns only the layout.
 */
export function AccountDetailView({
  detail,
  audit,
  auditLimit,
  override,
  archives,
  reports,
  reportsFailed,
}: {
  detail: AccountDetail;
  audit: AuditEntry[];
  /** The `p_limit` the audit was read with, so the list can say when there may be more. */
  auditLimit: number;
  override: FlightOverride | null;
  archives: CoupleArchive[];
  reports: ReportAboutAccount[];
  reportsFailed: boolean;
}) {
  const subscription = cancellability(detail.subscription.store, detail.subscription.active);
  const name = detail.profile.first_name?.trim();
  const email = detail.auth.email;
  const deletedAt = detail.auth.deleted_at;
  const reportCount = reports.filter((r) => !r.is_block_notice).length;
  const blockingThem = detail.counts.blocking_them;
  const lastActive = daysAgo(detail.profile.last_active_at);

  const sections = [
    { id: "overview", label: "Overview" },
    { id: "safety", label: "Safety" },
    { id: "grants", label: "Grants" },
    ...(archives.length > 0 ? [{ id: "archives", label: "Archives" }] : []),
    { id: "danger", label: "Danger zone", danger: true },
    { id: "history", label: "History" },
  ];

  return (
    <div className="account-page">
      <Link href="/admin/users" className="account-back">
        <ArrowLeft aria-hidden />
        Users
      </Link>

      <header className="account-identity">
        <h1>{name || email || "No name"}</h1>
        {name && <p className="account-identity-email">{email ?? "No email"}</p>}
        <p className="account-identity-meta">
          Joined {shortDate(detail.profile.created_at)} ·{" "}
          {lastActive ? `last active ${lastActive}` : "never active"}
        </p>

        <div className="account-badges">
          {deletedAt && (
            <StatusPill tone="error" icon={<Trash2 />}>
              Deleted {shortDate(deletedAt)}
            </StatusPill>
          )}
          {detail.subscription.active ? (
            <StatusPill tone={detail.subscription.tier?.toLowerCase() === "premium" ? "indigo" : "accent"}>
              {titleCase(detail.subscription.tier) ?? "Subscribed"}
              {detail.subscription.will_renew === false && " · not renewing"}
            </StatusPill>
          ) : (
            <StatusPill tone="neutral">No subscription</StatusPill>
          )}
          {detail.couple ? (
            <Link href={`/admin/users/${detail.couple.partner_id}`} className="pill pill-raised">
              <Heart aria-hidden />
              Paired with {detail.couple.partner_first_name || "someone"}
            </Link>
          ) : (
            <StatusPill tone="neutral">Not paired</StatusPill>
          )}
          {reportCount > 0 && (
            <a href="#safety" className="pill pill-error">
              <Flag aria-hidden />
              Reported {reportCount}
            </a>
          )}
          {blockingThem > 0 && (
            <a href="#safety" className="pill pill-warning">
              <ShieldOff aria-hidden />
              Blocked by {blockingThem}
            </a>
          )}
        </div>
      </header>

      {deletedAt && (
        <div className="account-notice" role="note">
          <Trash2 aria-hidden />
          <p className="flex-1">
            Deleted {shortDate(deletedAt)}. Sign-in is permanently disabled and cannot be restored.
          </p>
          <InfoTip label="Why a deleted account is still here">
            <p>
              The row stays on purpose. <code>delete-account</code> soft-deletes, so the foreign-key
              cascade never fires and takes the other partner&apos;s shared history with it.
            </p>
          </InfoTip>
        </div>
      )}

      <nav className="account-nav" aria-label="Sections of this account">
        {sections.map((s) => (
          <a key={s.id} href={`#${s.id}`} className={s.danger ? "is-danger" : undefined}>
            {s.label}
          </a>
        ))}
      </nav>

      <AccountSection id="overview" title="Overview" icon={<LayoutGrid aria-hidden className="text-muted-foreground" />}>
        <div className="account-grid">
          <AccountCard title="Subscription">
            <Facts>
              <Fact label="Status" value={detail.subscription.active ? "Active" : "None"} />
              <Fact label="Plan" value={titleCase(detail.subscription.tier) ?? "-"} />
              <Fact
                label="Bought via"
                value={subscription.label}
                alert={!subscription.ours && detail.subscription.active}
              />
              <Fact
                label="Renews"
                value={
                  detail.subscription.will_renew === null
                    ? "Unknown"
                    : detail.subscription.will_renew
                      ? "Yes"
                      : "No, cancelled"
                }
              />
              <Fact label="Since" value={shortDate(detail.subscription.started_at)} />
              <Fact label="Last checked" value={shortDate(detail.subscription.checked_at)} />
            </Facts>
          </AccountCard>

          <AccountCard
            title="Partner"
            action={
              detail.couple ? (
                <Link href={`/admin/users/${detail.couple.partner_id}`} className="account-card-link">
                  Open their account
                  <ArrowRight aria-hidden />
                </Link>
              ) : undefined
            }
          >
            {detail.couple ? (
              <Facts>
                <Fact label="Name" value={detail.couple.partner_first_name ?? "-"} />
                <Fact label="Email" value={detail.couple.partner_email ?? "-"} />
                <Fact label="Together since" value={shortDate(detail.couple.started_dating_on)} />
                <Fact label="Paired on" value={shortDate(detail.couple.created_at)} />
              </Facts>
            ) : (
              <p className="account-empty-line">Not currently paired.</p>
            )}
          </AccountCard>

          <AccountCard title="Activity">
            <Facts>
              <Fact label="Last active" value={shortDate(detail.profile.last_active_at)} />
              <Fact label="Last sign-in" value={shortDate(detail.auth.last_sign_in_at)} />
              <Fact label="Finished onboarding" value={shortDate(detail.profile.onboarding_completed_at)} />
              <Fact
                label="Dormancy warned"
                value={shortDate(detail.profile.dormancy_warned_at)}
                alert={Boolean(detail.profile.dormancy_warned_at)}
              />
              <Fact label="Sign-in methods" value={detail.auth.providers.join(", ") || "-"} />
              <Fact label="Timezone" value={detail.profile.timezone ?? "-"} />
            </Facts>
          </AccountCard>

          <AccountCard title="Content">
            {/* Counts only, and the note under them is the policy. */}
            <Facts>
              <Fact label="Flights tracked" value={detail.counts.flights_tracked} />
              <Fact label="Still tracking" value={detail.counts.flights_tracking_enabled} />
              <Fact label="Trips" value={detail.counts.trips} />
              <Fact label="Memories" value={detail.counts.memories} />
              {detail.flight_allowance && (
                <Fact
                  label="Flight allowance"
                  value={`${detail.flight_allowance.used ?? 0} of ${detail.flight_allowance.limit ?? "-"} this month`}
                />
              )}
            </Facts>
            <p className="account-hint">
              Counts only. Flights are never listed.
              <InfoTip label="Why flights are counts only">
                <p>
                  A hidden flight is hidden from the person&apos;s own partner, and a count answers the
                  question a list would.
                </p>
              </InfoTip>
            </p>
          </AccountCard>
        </div>
      </AccountSection>

      <AccountSection
        id="safety"
        title="Safety"
        icon={<ShieldAlert aria-hidden className={reportCount > 0 || blockingThem > 0 ? "text-destructive" : "text-muted-foreground"} />}
      >
        <div className="account-grid is-safety">
          <AccountReports reports={reports} loadFailed={reportsFailed} />
          <AccountCard title="Blocks">
            <Facts>
              <Fact label="People they blocked" value={detail.counts.blocked_by_them} />
              <Fact label="People blocking them" value={blockingThem} alert={blockingThem > 0} />
            </Facts>
          </AccountCard>
        </div>
      </AccountSection>

      <AccountGrants
        profileId={detail.profile.id}
        override={override}
        credits={detail.credits}
        tierLimit={detail.flight_allowance?.limit ?? null}
      />

      <AccountArchives archives={archives} />

      <AccountActions
        profileId={detail.profile.id}
        email={detail.auth.email ?? ""}
        alreadyDeleted={Boolean(deletedAt)}
        couple={
          detail.couple
            ? { id: detail.couple.id, partnerFirstName: detail.couple.partner_first_name }
            : null
        }
        subscriptionStore={detail.subscription.store}
        subscriptionActive={detail.subscription.active}
      />

      <AccountHistory entries={audit} limit={auditLimit} />
    </div>
  );
}

/** "premium" -> "Premium". The tier arrives as the entitlement's lowercase id. */
function titleCase(value: string | null): string | null {
  if (!value) return null;
  return value.charAt(0).toUpperCase() + value.slice(1);
}
