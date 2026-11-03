import { describe, expect, it, vi } from "vitest";
import { QueryClient } from "@tanstack/react-query";
import { accountKeys, fetchAccountsUpTo, invalidateAccountLists, LIST_ACCOUNTS_MAX_PAGE } from "./accountQueries";

describe("invalidateAccountLists", () => {
  it("marks every Users-page read stale after an account action", async () => {
    const client = new QueryClient();
    const keys = [accountKeys.page(0), accountKeys.page(3), accountKeys.everyone(), accountKeys.reported(), accountKeys.lookup("a@b.co")];
    for (const key of keys) client.setQueryData(key, []);

    await invalidateAccountLists(client);

    for (const key of keys) expect(client.getQueryState(key)?.isInvalidated, JSON.stringify(key)).toBe(true);
  });

  it("leaves other console data alone", async () => {
    const client = new QueryClient();
    client.setQueryData(["admin", "features", {}], []);
    await invalidateAccountLists(client);
    expect(client.getQueryState(["admin", "features", {}])?.isInvalidated).toBe(false);
  });
});

describe("fetchAccountsUpTo", () => {
  /** admin_list_accounts as the database has it: never more than 100 rows a call. */
  function database(total: number) {
    return vi.fn(async (limit: number, offset: number) => {
      const size = Math.max(0, Math.min(limit, LIST_ACCOUNTS_MAX_PAGE, total - offset));
      return Array.from({ length: size }, (_, i) => ({ n: offset + i }));
    });
  }

  it("reads past the function's 100-row cap", async () => {
    const fetchPage = database(250);
    const rows = await fetchAccountsUpTo(fetchPage, 1000);
    expect(rows).toHaveLength(250);
    expect(rows.at(-1)).toEqual({ n: 249 });
  });

  it("stops at the limit", async () => {
    const fetchPage = database(5000);
    const rows = await fetchAccountsUpTo(fetchPage, 1000);
    expect(rows).toHaveLength(1000);
    expect(fetchPage).toHaveBeenCalledTimes(10);
  });

  it("stops after a short page without asking again", async () => {
    const fetchPage = database(40);
    await fetchAccountsUpTo(fetchPage, 1000);
    expect(fetchPage).toHaveBeenCalledTimes(1);
  });
});
