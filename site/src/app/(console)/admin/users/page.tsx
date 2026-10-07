"use client";

import { useState } from "react";
import Link from "next/link";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight, Loader2, Search } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { ConsoleEmpty, ConsolePageHead } from "@/components/console/ConsoleUI";
import { SegmentedControl } from "@/components/site/SegmentedControl";
import { StatusPill } from "@/components/site/StatusPill";
import { createClient } from "@/lib/supabase/client";
import type { AccountSearchResult } from "@/lib/console/accountDetail";

const PAGE_SIZE = 20;
/** How many accounts a filtered view loads to filter in the browser. admin_list_accounts pages but
 *  does not filter, so a filter reads this many and filters them here. */
const FILTER_LIMIT = 1000;

const FILTERS = [
  { value: "all", label: "All" },
  { value: "active", label: "Active" },
  { value: "deleted", label: "Deleted" },
  { value: "paired", label: "Paired" },
  { value: "subscribed", label: "Subscribed" },
] as const;
type Filter = (typeof FILTERS)[number]["value"];

function matches(row: AccountSearchResult, filter: Filter) {
  switch (filter) {
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

function joined(iso: string) {
  return new Date(iso).toLocaleDateString("en-AU", { day: "numeric", month: "short", year: "numeric", timeZone: "Australia/Melbourne" });
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
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(0);
  const [filter, setFilter] = useState<Filter>("all");
  const trimmed = query.trim();
  const searching = trimmed.length >= 3;
  const filtering = !searching && filter !== "all";

  const list = useQuery({
    queryKey: ["admin", "accounts", page],
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
    queryKey: ["admin", "accounts", "all"],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("admin_list_accounts", { p_limit: FILTER_LIMIT, p_offset: 0 });
      if (error) throw error;
      return (data ?? []) as ListRow[];
    },
    enabled: filtering,
  });

  const search = useQuery({
    queryKey: ["admin", "lookup", trimmed],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("admin_lookup_account", { p_query: trimmed });
      if (error) throw error;
      return (data ?? []) as AccountSearchResult[];
    },
    enabled: searching,
  });

  const filtered = filtering ? (everyone.data ?? []).filter((row) => matches(row, filter)) : [];
  const rows: AccountSearchResult[] = searching
    ? (search.data ?? [])
    : filtering
      ? filtered.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE)
      : (list.data ?? []);
  const total = filtering ? filtered.length : (list.data?.[0]?.total_count ?? 0);
  const isFetching = searching ? search.isFetching : filtering ? everyone.isFetching : list.isFetching;
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
            onChange={(e) => {
              setQuery(e.target.value);
              setPage(0);
            }}
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
            onChange={(value) => {
              setFilter(value);
              setPage(0);
            }}
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
                  <td className="num muted">{joined(row.created_at)}</td>
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
            <Button variant="outline" size="sm" disabled={page === 0 || isFetching} onClick={() => setPage((p) => Math.max(0, p - 1))}>
              <ChevronLeft className="h-4 w-4" aria-hidden />
              Newer
            </Button>
            <Button variant="outline" size="sm" disabled={page >= lastPage || isFetching} onClick={() => setPage((p) => p + 1)}>
              Older
              <ChevronRight className="h-4 w-4" aria-hidden />
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
