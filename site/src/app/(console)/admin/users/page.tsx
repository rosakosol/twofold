"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { Loader2, Search } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/client";
import type { AccountSearchResult } from "@/lib/console/accountDetail";

/**
 * Finding the person who emailed.
 *
 * Deliberately a search box and not a list. There is no "browse all accounts" here and there
 * should not be: every ticket arrives with a key — an email address, a profile id from an earlier
 * thread, or the invite code that would not redeem — and a console you can scroll through is one
 * that invites looking at people for no reason.
 *
 * `admin_lookup_account` matches email exactly rather than by prefix, so this is a lookup rather
 * than a directory. It returns only enough to pick the right row; everything else needs the detail
 * page, which is logged.
 */
export default function UsersPage() {
  const [query, setQuery] = useState("");
  const trimmed = query.trim();

  const { data, isFetching, error } = useQuery({
    queryKey: ["admin", "lookup", trimmed],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("admin_lookup_account", { p_query: trimmed });
      if (error) throw error;
      return (data ?? []) as AccountSearchResult[];
    },
    // Only on a plausible key. Firing per keystroke would put a query behind every character of an
    // email address, and the first few characters of one match nothing by design.
    enabled: trimmed.length >= 3,
  });

  return (
    <div className="space-y-6">
      <header>
        <h1 className="font-heading text-xl font-semibold tracking-tight">Accounts</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Search by email address, profile id, or invite code.
        </p>
      </header>

      <div className="relative max-w-md">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          className="pl-9"
          placeholder="someone@example.com"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          autoComplete="off"
          spellCheck={false}
        />
        {isFetching && (
          <Loader2 className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-muted-foreground" />
        )}
      </div>

      {error && (
        <p className="text-sm text-destructive">
          That search couldn&apos;t run. You may not hold the support role.
        </p>
      )}

      {trimmed.length >= 3 && !isFetching && (data?.length ?? 0) === 0 && !error && (
        <p className="text-sm text-muted-foreground">
          No account matches that. Email is matched exactly — check for a typo, or ask them which
          address they signed up with.
        </p>
      )}

      {(data?.length ?? 0) > 0 && (
        <Card>
          <CardContent className="p-0">
            <ul className="divide-y">
              {data!.map((row) => (
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
                      {/* A deleted account still appears, because delete-account soft-deletes:
                          auth.users keeps the row so the FK cascade never takes the other
                          partner's shared history with it. Saying so prevents the obvious wrong
                          conclusion that the deletion did not work. */}
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
    </div>
  );
}
