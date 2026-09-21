/**
 * The shape `public.admin_account_detail` returns.
 *
 * Declared here rather than generated, because the function returns `jsonb` — deliberately, so the
 * payload can grow as support needs one more fact without every caller needing a signature change.
 * The cost of that is this file, which has to be kept in step with the migration by hand. The
 * migration is the source of truth; if the two disagree, this one is wrong.
 *
 * Note what is absent, and stays absent: no memories, no photos, no answers, no documents, and no
 * flight rows — flights are a count. `flights.shared = false` means "my partner cannot see this
 * flight", which the privacy policy promises by name, and a support screen that listed those rows
 * would break that promise for the people least able to absorb it.
 */
export interface AccountDetail {
  profile: {
    id: string;
    first_name: string;
    created_at: string;
    last_active_at: string | null;
    onboarding_completed_at: string | null;
    dormancy_warned_at: string | null;
    timezone: string | null;
    locale: string | null;
  };
  auth: {
    email: string | null;
    email_confirmed_at: string | null;
    last_sign_in_at: string | null;
    /** Set by delete-account's soft delete: sign-in is permanently disabled, the row remains so the
     * FK cascade never fires and the other partner's shared history survives. */
    deleted_at: string | null;
    providers: string[];
  };
  subscription: {
    active: boolean;
    tier: string | null;
    /** Null means the webhook has not seen this account since the column existed — "unknown",
     * never "not a store subscription". Decides what support can offer. */
    store: string | null;
    will_renew: boolean | null;
    started_at: string | null;
    checked_at: string | null;
  };
  couple: {
    id: string;
    started_dating_on: string | null;
    created_at: string;
    partner_id: string;
    partner_first_name: string | null;
    partner_email: string | null;
  } | null;
  counts: {
    flights_tracked: number;
    flights_tracking_enabled: number;
    trips: number;
    memories: number;
    blocked_by_them: number;
    blocking_them: number;
  };
  credits: {
    streak_repair_unused: number;
    record_export_unused: number;
  };
  flight_allowance: { tier: string | null; limit: number | null; used: number | null } | null;
}

export interface AccountSearchResult {
  profile_id: string;
  email: string | null;
  first_name: string;
  created_at: string;
  last_active_at: string | null;
  subscription_tier: string | null;
  subscription_active: boolean;
  has_partner: boolean;
  deleted_at: string | null;
}

export interface AuditEntry {
  actor_id: string;
  actor_email: string | null;
  action: string;
  reason: string | null;
  details: unknown;
  occurred_at: string;
}

/** What support can actually do about this subscription, which is the first question any
 * subscription ticket resolves to. Mirrors the portal's own rule: anything not positively known to
 * be a web store is not ours to cancel. */
export function cancellability(store: string | null, active: boolean): {
  label: string;
  ours: boolean;
} {
  if (!active) return { label: "No active subscription", ours: false };
  const normalised = store?.trim().toLowerCase() ?? "";
  if (normalised === "stripe" || normalised === "rc_billing") {
    return { label: "Web — ours to cancel", ours: true };
  }
  if (normalised === "") {
    return { label: "Store unknown — not safe to cancel", ours: false };
  }
  if (normalised === "promotional") return { label: "Promotional grant — no billing to end", ours: false };
  return { label: `${normalised.replace(/_/g, " ")} — not ours to cancel`, ours: false };
}
