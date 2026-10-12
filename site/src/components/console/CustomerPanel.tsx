"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { ExternalLink, Loader2, UserRound } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { cancellability, type AccountDetail } from "@/lib/console/accountDetail";
import { cn } from "@/lib/utils";

export interface OtherConversation {
  threadId: string;
  subject: string | null;
  status: string;
  lastAt: string;
}

/**
 * Who you're talking to, beside the conversation: the account behind the address, its plan, its
 * partner, and their other conversations, so a reply doesn't start with a trip to the Users page.
 *
 * Read through `admin_account_detail`, the same call the account page makes, so it shows the same
 * facts and is recorded the same way: opening a conversation with this panel showing is looking at
 * the account. Counts only, like that page, never memories, answers or flight rows.
 */
export function CustomerPanel({
  profileId,
  email,
  reported,
  otherConversations,
  onSelectConversation,
}: {
  profileId: string | null;
  email: string | null;
  /** Set when this conversation is an abuse report: who it is about, shown above the reporter. */
  reported: { profileId: string | null; name: string | null } | null;
  otherConversations: OtherConversation[];
  onSelectConversation: (threadId: string) => void;
}) {
  const [detail, setDetail] = useState<AccountDetail | null | undefined>(undefined);

  useEffect(() => {
    if (!profileId) return;
    let cancelled = false;
    (async () => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("admin_account_detail", {
        p_profile_id: profileId,
        p_reason: "Viewed beside a support conversation",
      });
      if (!cancelled) setDetail(error || !data ? null : (data as unknown as AccountDetail));
    })();
    return () => {
      cancelled = true;
    };
  }, [profileId]);

  if (!profileId) {
    return (
      <div className="space-y-2 p-4 text-sm">
        <ReportedSection reported={reported} />
        <PanelHeading>Customer</PanelHeading>
        <p className="break-all">{email ?? "No address"}</p>
        <p className="text-xs text-muted-foreground">
          No Twofold account uses this email. They may have signed up with a different address, or
          with Apple&apos;s Hide My Email.
        </p>
        <Conversations items={otherConversations} onSelect={onSelectConversation} />
      </div>
    );
  }

  if (detail === undefined) {
    return (
      <div className="flex justify-center p-6">
        <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (detail === null) {
    return (
      <div className="space-y-2 p-4 text-sm">
        <ReportedSection reported={reported} />
        <PanelHeading>Customer</PanelHeading>
        <p className="text-xs text-muted-foreground">Couldn&apos;t load this account.</p>
        <OpenAccount profileId={profileId} />
      </div>
    );
  }

  const subscription = cancellability(detail.subscription.store, detail.subscription.active);

  return (
    <div className="space-y-5 p-4 text-sm">
      <ReportedSection reported={reported} />
      <div className="space-y-1">
        <div className="flex items-center gap-2">
          <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-muted">
            <UserRound className="h-4 w-4 text-muted-foreground" aria-hidden />
          </span>
          <div className="min-w-0">
            <p className="truncate font-medium">{detail.profile.first_name || "No name"}</p>
            <p className="truncate text-xs text-muted-foreground">{detail.auth.email ?? "No email"}</p>
          </div>
        </div>
        {detail.auth.deleted_at && (
          <p className="pill pill-error mt-1 w-fit">Deleted {formatDate(detail.auth.deleted_at)}</p>
        )}
        <OpenAccount profileId={profileId} />
      </div>

      <Section title="Account">
        <Row label="Joined" value={formatDate(detail.profile.created_at)} />
        <Row label="Last active" value={formatDate(detail.profile.last_active_at)} />
        <Row label="Last sign-in" value={formatDate(detail.auth.last_sign_in_at)} />
        <Row label="Signs in with" value={detail.auth.providers.join(", ") || "—"} />
        <Row label="Timezone" value={detail.profile.timezone ?? "—"} />
      </Section>

      <Section title="Subscription">
        <Row
          label="Plan"
          value={detail.subscription.active ? (detail.subscription.tier ?? "Active") : "None"}
          strong={detail.subscription.active}
        />
        {detail.subscription.active && (
          <>
            <Row label="Bought via" value={subscription.label} />
            <Row
              label="Renews"
              value={
                detail.subscription.will_renew === null ? "Unknown" : detail.subscription.will_renew ? "Yes" : "No, cancelled"
              }
            />
          </>
        )}
      </Section>

      <Section title="Partner">
        {detail.couple ? (
          <>
            <Row label="Name" value={detail.couple.partner_first_name ?? "—"} />
            <Row label="Email" value={detail.couple.partner_email ?? "—"} />
            <Row label="Paired" value={formatDate(detail.couple.created_at)} />
            <Link
              href={`/admin/users/${detail.couple.partner_id}`}
              className="inline-flex items-center gap-1 text-xs underline underline-offset-2"
            >
              Open partner&apos;s account <ExternalLink className="h-3 w-3" aria-hidden />
            </Link>
          </>
        ) : (
          <p className="text-xs text-muted-foreground">Not paired.</p>
        )}
      </Section>

      <Section title="Activity">
        <Row label="Trips" value={String(detail.counts.trips)} />
        <Row label="Memories" value={String(detail.counts.memories)} />
        <Row label="Flights tracked" value={String(detail.counts.flights_tracked)} />
        <Row label="They've blocked" value={String(detail.counts.blocked_by_them)} />
        <Row
          label="Blocked by"
          value={String(detail.counts.blocking_them)}
          warn={detail.counts.blocking_them > 0}
        />
      </Section>

      <Conversations items={otherConversations} onSelect={onSelectConversation} />
    </div>
  );
}

/** Above the reporter, in the error colour: on a report, who it is about is the first question. The
 * full picture (history, blocks, what to do) is the card in the conversation itself. */
function ReportedSection({ reported }: { reported: { profileId: string | null; name: string | null } | null }) {
  if (!reported) return null;
  return (
    <section className="space-y-1 rounded-md border border-destructive/40 bg-destructive/5 p-2.5">
      <h3 className="text-xs font-medium uppercase tracking-wide text-destructive">Reported in this conversation</h3>
      <p className="text-sm font-medium">{reported.name || (reported.profileId ? "Unnamed account" : "Not recorded")}</p>
      {reported.profileId ? (
        <Link
          href={`/admin/users/${reported.profileId}`}
          className="inline-flex items-center gap-1 text-xs underline underline-offset-2"
        >
          Open their account <ExternalLink className="h-3 w-3" aria-hidden />
        </Link>
      ) : (
        <p className="text-xs text-muted-foreground">Sent before reports named an account.</p>
      )}
    </section>
  );
}

function PanelHeading({ children }: { children: React.ReactNode }) {
  return <h3 className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{children}</h3>;
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="space-y-1.5">
      <PanelHeading>{title}</PanelHeading>
      {children}
    </section>
  );
}

function Row({ label, value, strong, warn }: { label: string; value: string; strong?: boolean; warn?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-3 text-xs">
      <span className="shrink-0 text-muted-foreground">{label}</span>
      <span className={cn("truncate text-right", strong && "font-medium", warn && "font-medium text-destructive")}>
        {value}
      </span>
    </div>
  );
}

function OpenAccount({ profileId }: { profileId: string }) {
  return (
    <Link
      href={`/admin/users/${profileId}`}
      className="inline-flex items-center gap-1 text-xs underline underline-offset-2"
    >
      Open full account <ExternalLink className="h-3 w-3" aria-hidden />
    </Link>
  );
}

/** Their other conversations among the ones loaded, so "have they written before?" is a glance. */
function Conversations({ items, onSelect }: { items: OtherConversation[]; onSelect: (threadId: string) => void }) {
  return (
    <Section title="Other conversations">
      {items.length === 0 ? (
        <p className="text-xs text-muted-foreground">None in this view.</p>
      ) : (
        <ul className="space-y-0.5">
          {items.map((item) => (
            <li key={item.threadId}>
              <button
                type="button"
                onClick={() => onSelect(item.threadId)}
                className="flex w-full items-baseline justify-between gap-2 rounded-md px-1.5 py-1 text-left text-xs hover:bg-accent"
              >
                <span className="truncate">{item.subject || "(no subject)"}</span>
                <span className="shrink-0 text-muted-foreground">
                  {item.status === "open" ? "Open" : formatDate(item.lastAt)}
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </Section>
  );
}

function formatDate(value: string | null): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}
