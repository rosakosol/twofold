"use client";

import { useState } from "react";
import Link from "next/link";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight, Loader2, Search } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { createClient } from "@/lib/supabase/client";
import type { AccountSearchResult } from "@/lib/console/accountDetail";

const PAGE_SIZE = 20;

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
  const trimmed = query.trim();
  const searching = trimmed.length >= 3;

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
    enabled: !searching,
    // Without this the table empties to a spinner on every page change and the layout jumps. The
    // previous page stays put until the next one lands, which is what paging through a list is
    // supposed to feel like.
    placeholderData: keepPreviousData,
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

  const rows: AccountSearchResult[] = searching ? (search.data ?? []) : (list.data ?? []);
  const total = list.data?.[0]?.total_count ?? 0;
  const isFetching = searching ? search.isFetching : list.isFetching;
  const error = searching ? search.error : list.error;
  const lastPage = Math.max(0, Math.ceil(total / PAGE_SIZE) - 1);

  return (
    <div className="space-y-6">
      <header>
        <h1 className="font-heading text-xl font-semibold tracking-tight">Users</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          {searching
            ? "Searching by email address, profile id, or invite code."
            : total > 0
              ? `${total.toLocaleString()} account${total === 1 ? "" : "s"}, newest first.`
              : "Everyone who has signed up, newest first."}
        </p>
      </header>

      <div className="relative max-w-md">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          className="pl-9"
          placeholder="Search email, profile id, or invite code"
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setPage(0);
          }}
          autoComplete="off"
          spellCheck={false}
        />
        {isFetching && (
          <Loader2 className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-muted-foreground" />
        )}
      </div>

      {error && (
        <p className="text-sm text-destructive">
          That didn&apos;t load. You may not hold the support role.
        </p>
      )}

      {!error && rows.length === 0 && !isFetching && (
        <p className="text-sm text-muted-foreground">
          {searching
            ? "No account matches that. Email is matched exactly — check for a typo, or ask which address they signed up with."
            : "No accounts yet."}
        </p>
      )}

      {rows.length === 0 && isFetching && <Skeleton className="h-64 w-full rounded-lg" />}

      {rows.length > 0 && (
        <Card>
          <CardContent className="p-0">
            <ul className="divide-y">
              {rows.map((row) => (
                <li key={row.profile_id}>
                  <Link
                    href={`/admin/users/${row.profile_id}`}
                    className="flex items-center justify-between gap-4 px-4 py-3 transition-colors hover:bg-accent"
                  >
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium">{row.email ?? "no email"}</p>
                      <p className="truncate text-xs text-muted-foreground">
                        {row.first_name || "no name"} · joined{" "}
                        {new Date(row.created_at).toLocaleDateString()}
                      </p>
                    </div>
                    <div className="flex shrink-0 items-center gap-2">
                      {row.deleted_at && <Badge variant="destructive">Deleted</Badge>}
                      {row.has_partner && <Badge variant="outline">Paired</Badge>}
                      {row.subscription_active && (
                        <Badge variant="secondary">{row.subscription_tier ?? "active"}</Badge>
                      )}
                    </div>
                  </Link>
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>
      )}

      {!searching && total > PAGE_SIZE && (
        <div className="flex items-center justify-between">
          <p className="text-sm text-muted-foreground tabular-nums">
            {page * PAGE_SIZE + 1}–{Math.min((page + 1) * PAGE_SIZE, total)} of{" "}
            {total.toLocaleString()}
          </p>
          <div className="flex gap-2">
            <Button
              variant="outline"
              size="sm"
              disabled={page === 0 || isFetching}
              onClick={() => setPage((p) => Math.max(0, p - 1))}
            >
              <ChevronLeft className="h-4 w-4" />
              Newer
            </Button>
            <Button
              variant="outline"
              size="sm"
              disabled={page >= lastPage || isFetching}
              onClick={() => setPage((p) => p + 1)}
            >
              Older
              <ChevronRight className="h-4 w-4" />
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
