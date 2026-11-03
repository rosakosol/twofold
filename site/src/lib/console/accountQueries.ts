import type { QueryClient } from "@tanstack/react-query";

/**
 * The Users page's reads, keyed under one prefix so an account action can mark them all stale.
 *
 * Account actions (delete, disconnect, cancel, grant, purge) used to call only `router.refresh()`,
 * which re-renders the server-rendered account page but never touches this cache. With the global
 * 30s staleTime, going back to Users showed a just-deleted account as Active. The search and the
 * reported-accounts read sat under other prefixes, so even a prefix invalidation would have missed
 * them; now everything is under ["admin", "accounts"].
 */
export const accountKeys = {
  all: ["admin", "accounts"] as const,
  page: (page: number) => ["admin", "accounts", "page", page] as const,
  everyone: () => ["admin", "accounts", "everyone"] as const,
  reported: () => ["admin", "accounts", "reported"] as const,
  lookup: (query: string) => ["admin", "accounts", "lookup", query] as const,
};

export function invalidateAccountLists(queryClient: QueryClient) {
  return queryClient.invalidateQueries({ queryKey: accountKeys.all });
}

/** `admin_list_accounts` clamps `p_limit` to this (20261109001300: `least(…, 100)`). */
export const LIST_ACCOUNTS_MAX_PAGE = 100;

/**
 * Up to `limit` accounts, newest first, read a page at a time.
 *
 * The filtered views asked for 1000 in one call and got 100, because the function clamps, so
 * "Deleted" or "Subscribed" quietly covered only the newest hundred accounts while the page said
 * a thousand.
 */
export async function fetchAccountsUpTo<T>(
  fetchPage: (limit: number, offset: number) => Promise<T[]>,
  limit: number,
): Promise<T[]> {
  const rows: T[] = [];
  while (rows.length < limit) {
    const size = Math.min(LIST_ACCOUNTS_MAX_PAGE, limit - rows.length);
    const page = await fetchPage(size, rows.length);
    rows.push(...page);
    if (page.length < size) break;
  }
  return rows;
}
