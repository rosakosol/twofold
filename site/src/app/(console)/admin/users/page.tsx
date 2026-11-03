"use client";

import { Suspense, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight, Loader2, Search } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { ConsoleEmpty, ConsolePageHead } from "@/components/console/ConsoleUI";
import { SegmentedControl } from "@/components/site/SegmentedControl";
import { StatusPill } from "@/components/site/StatusPill";
import { createClient } from "@/lib/supabase/client";
import type { AccountSearchResult, ReportedAccount } from "@/lib/console/accountDetail";
import { accountKeys, fetchAccountsUpTo } from "@/lib/console/accountQueries";
import { shortDate } from "@/lib/console/format";
import { useDebouncedValue } from "@/hooks/useDebouncedValue";

const PAGE_SIZE = 20;
/** How many accounts a filtered view loads to filter in the browser. admin_list_accounts pages but
 *  does not filter, so a filter reads this many, 100 a call (the function's cap), and filters them
 *  here. */
const FILTER_LIMIT = 1000;

const FILTERS = [
  { value: "all", label: "All" },
  { value: "active", label: "Active" },
  { value: "deleted", label: "Deleted" },
  { value: "paired", label: "Paired" },
  { value: "subscribed", label: "Subscribed" },
  { value: "reported", label: "Reported" },
] as const;
type Filter = (typeof FILTERS)[number]["value"];

function matches(row: AccountSearchResult, filter: Filter, reported: Map<string, ReportedAccount>) {
  switch (filter) {
    case "reported":
      return (reported.get(row.profile_id)?.report_count ?? 0) > 0;
    case "active":
      return !row.deleted_at;
    case "deleted":
      return Boolean(row.deleted_at);
    case "paired":
      return !row.deleted_at && row.has_partner;
    case "subscribed":
      return !row.deleted_at && row.subscription_active;
    default:
      return true;
  }
}

/** "a1b2c3…9f0e": enough of a deleted account's id to find it again, not the whole thing. */
function shortId(id: string) {
  const plain = id.replace(/-/g, "");
  return `${plain.slice(0, 6)}…${plain.slice(-4)}`;
}

interface ListRow extends AccountSearchResult {
  total_count: number;
}

/**
 * Everyone who has signed up, newest first — and a search box for when somebody has written in.
 *
 * The list and the search answer different questions and so are different queries: "who is there"
 * versus "find this person". Typing switches to the search, which matches an email exactly rather
 * than by prefix, because a lookup that also does partial matching quietly becomes a directory
 * with a different shape.
 *
 * Neither is audited. They say who exists, not who anybody is; `admin_account_detail` stays the
 * audited call because opening a row is still what turns it into a person.
 */
export default function UsersPage() {
  // useSearchParams needs a Suspense boundary above it.
  return (
    <Suspense>
      <Users />
    </Suspense>
  );
}

function isFilter(value: string | null): value is Filter {
  return FILTERS.some((f) => f.value === value);
}

/**
 * Search, page and filter live in the URL (?q=, ?page=, ?filter=), as the public board's do, so
 * opening an account and coming back lands where you were rather than on page 1 of All.
 */
function Users() {
  const router = useRouter();
  const params = useSearchParams();
  const committedQuery = params.get("q") ?? "";
  const page = Math.max(0, (Number.parseInt(params.get("page") ?? "1", 10) || 1) - 1);
  const rawFilter = params.get("filter");
  const filter: Filter = isFilter(rawFilter) ? rawFilter : "all";

  function setParams(next: { q?: string; page?: number; filter?: Filter }) {
    const updated = new URLSearchParams(params.toString());
    const apply = (key: string, value: string | undefined) => (value ? updated.set(key, value) : updated.delete(key));
    if (next.q !== undefined) apply("q", next.q.trim() || undefined);
    if (next.filter !== undefined) apply("filter", next.filter === "all" ? undefined : next.filter);
    if (next.page !== undefined) apply("page", next.page > 0 ? String(next.page + 1) : undefined);
    const qs = updated.toString();
    router.replace(qs ? `/admin/users?${qs}` : "/admin/users", { scroll: false });
  }

  // What is typed, and what has been searched for. Each lookup is a round trip and a new query key,
  // so the search waits until typing pauses rather than firing for every character past the third.
  const [query, setQuery] = useState(committedQuery);
  const [syncedQuery, setSyncedQuery] = useState(committedQuery);
  if (syncedQuery !== committedQuery) {
    setSyncedQuery(committedQuery);
    // Our own update just echoing back leaves the draft alone (a trailing space included); a URL
    // changed from outside (back, forward) replaces it.
    if (committedQuery !== query.trim()) setQuery(committedQuery);
  }
  const debouncedQuery = useDebouncedValue(query);
  useEffect(() => {
    if (debouncedQuery.trim() !== committedQuery.trim()) setParams({ q: debouncedQuery, page: 0 });
    // Only when the typing settles; setParams reads the latest params itself.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [debouncedQuery]);

  const trimmed = committedQuery.trim();
  const searching = trimmed.length >= 3;
  const filtering = !searching && filter !== "all";

  const list = useQuery({
    queryKey: accountKeys.page(page),
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("admin_list_accounts", {
        p_limit: PAGE_SIZE,
        p_offset: page * PAGE_SIZE,
      });
      if (error) throw error;
      return (data ?? []) as ListRow[];
    },
    enabled: !searching && !filtering,
    // The previous page stays put until the next one lands, rather than emptying to a spinner.
    placeholderData: keepPreviousData,
  });

  const everyone = useQuery({
    queryKey: accountKeys.everyone(),
    queryFn: () => {
      const supabase = createClient();
      return fetchAccountsUpTo(async (limit, offset) => {
        const { data, error } = await supabase.rpc("admin_list_accounts", { p_limit: limit, p_offset: offset });
        if (error) throw error;
        return (data ?? []) as ListRow[];
      }, FILTER_LIMIT);
    },
    enabled: filtering,
  });

  // Every reported account, with counts: one small read, keyed by id, that both the Reports column
  // and the Reported filter look up in. Reporter identities stay on the account page.
  const reportCounts = useQuery({
    queryKey: accountKeys.reported(),
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("admin_reported_accounts", { p_limit: 5000 });
      if (error) throw error;
      return new Map(((data ?? []) as ReportedAccount[]).map((row) => [row.profile_id, row]));
    },
  });
  const reported = reportCounts.data ?? new Map<string, ReportedAccount>();

  const search = useQuery({
    queryKey: accountKeys.lookup(trimmed),
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("admin_lookup_account", { p_query: trimmed });
      if (error) throw error;
      return (data ?? []) as AccountSearchResult[];
    },
    enabled: searching,
  });

  const filtered = filtering ? (everyone.data ?? []).filter((row) => matches(row, filter, reported)) : [];
  const rows: AccountSearchResult[] = searching
    ? (search.data ?? [])
    : filtering
      ? filtered.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE)
      : (list.data ?? []);
  const total = filtering ? filtered.length : (list.data?.[0]?.total_count ?? 0);
  const isFetching = searching
    ? search.isFetching
    : filtering
      ? everyone.isFetching || (filter === "reported" && reportCounts.isFetching)
      : list.isFetching;
  const error = searching ? search.error : filtering ? everyone.error : list.error;
  const lastPage = Math.max(0, Math.ceil(total / PAGE_SIZE) - 1);
  const capped = filtering && (everyone.data?.[0]?.total_count ?? 0) > FILTER_LIMIT;

  return (
    <div>
      <ConsolePageHead
        title="Users"
        description={
          searching
            ? "Searching by email address, profile id or invite code."
            : "Everyone who has signed up, newest first. Opening an account is recorded in the audit log."
        }
      />

      <div className="console-filters">
        <div className="console-search relative">
          <label className="sr-only" htmlFor="user-search">
            Search email, profile id or invite code
          </label>
          <Search className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <Input
            id="user-search"
            type="search"
            className="pl-11"
            placeholder="Search email, profile id or invite code"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            autoComplete="off"
            spellCheck={false}
          />
          {isFetching && (
            <Loader2 className="absolute right-4 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-muted-foreground" aria-hidden />
          )}
        </div>
        {!searching && (
          <SegmentedControl
            label="Show"
            options={FILTERS}
            value={filter}
            onChange={(value) => setParams({ filter: value, page: 0 })}
          />
        )}
      </div>

      {error && <p className="field-error">That didn&apos;t load. You may not hold the support role.</p>}

      {capped && (
        <p className="field-hint">
          This filter covers the newest {FILTER_LIMIT.toLocaleString()} accounts. Search for anyone older.
        </p>
      )}

      {!error && rows.length === 0 && !isFetching && (
        <ConsoleEmpty title={searching ? "No account matches that" : filtering ? "No accounts in this view" : "No accounts yet"}>
          {searching ? "Email is matched exactly. Check for a typo, or ask which address they signed up with." : undefined}
        </ConsoleEmpty>
      )}

      {rows.length === 0 && isFetching && <Skeleton className="h-64 w-full rounded-2xl" />}

      {rows.length > 0 && (
        <div className="console-table-wrap">
          <table className="console-table">
            <thead>
              <tr>
                <th scope="col">Account</th>
                <th scope="col">Name</th>
                <th scope="col">Joined</th>
                <th scope="col">Status</th>
                <th scope="col">Partner</th>
                <th scope="col">Plan</th>
                <th scope="col" className="num">Reports</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.profile_id}>
                  <td>
                    <Link href={`/admin/users/${row.profile_id}`} className="console-row-link">
                      {row.deleted_at ? (
                        <>
                          Deleted account <span className="console-mono muted">{shortId(row.profile_id)}</span>
                        </>
                      ) : (
                        (row.email ?? "No email")
                      )}
                    </Link>
                  </td>
                  <td className={row.first_name ? undefined : "muted"}>{row.first_name || "None"}</td>
                  <td className="num muted">{shortDate(row.created_at)}</td>
                  <td>
                    {row.deleted_at ? (
                      <StatusPill tone="error">Deleted</StatusPill>
                    ) : (
                      <StatusPill tone="success">Active</StatusPill>
                    )}
                  </td>
                  <td className="muted">{row.has_partner ? "Connected" : "None"}</td>
                  <td>
                    {row.subscription_active ? (
                      <StatusPill tone={row.subscription_tier === "premium" ? "indigo" : "accent"}>
                        {row.subscription_tier === "premium" ? "Premium" : row.subscription_tier === "plus" ? "Plus" : "Active"}
                      </StatusPill>
                    ) : (
                      <span className="muted">None</span>
                    )}
                  </td>
                  <td className="num">
                    <ReportCount row={reported.get(row.profile_id)} failed={reportCounts.isError} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {!searching && total > PAGE_SIZE && (
        <div className="console-pager">
          <p className="num">
            Showing {page * PAGE_SIZE + 1} to {Math.min((page + 1) * PAGE_SIZE, total)} of {total.toLocaleString()}
          </p>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" disabled={page === 0 || isFetching} onClick={() => setParams({ page: Math.max(0, page - 1) })}>
              <ChevronLeft className="h-4 w-4" aria-hidden />
              Newer
            </Button>
            <Button variant="outline" size="sm" disabled={page >= lastPage || isFetching} onClick={() => setParams({ page: page + 1 })}>
              Older
              <ChevronRight className="h-4 w-4" aria-hidden />
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}

/** A reported account's report count, red once more than one person has reported them; a dash
 *  for everyone else. Block notices are not reports and are not counted here. */
function ReportCount({ row, failed }: { row: ReportedAccount | undefined; failed: boolean }) {
  // A dash means "no reports"; when the counts didn't load it would be a false one.
  if (failed) {
    return (
      <span className="muted" title="Report counts didn't load">
        ?
      </span>
    );
  }
  if (!row || row.report_count === 0) return <span className="muted">-</span>;
  const title = `${row.report_count} ${row.report_count === 1 ? "report" : "reports"} from ${row.reporter_count} ${
    row.reporter_count === 1 ? "person" : "people"
  }`;
  return (
    <span title={title}>
      <StatusPill tone={row.reporter_count > 1 ? "error" : "warning"}>{row.report_count}</StatusPill>
    </span>
  );
}
