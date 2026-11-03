"use client";

import { useCallback } from "react";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { invalidateAccountLists } from "@/lib/console/accountQueries";

/**
 * What every account action calls once it has succeeded. Two caches hold the account: the
 * server-rendered account page (router.refresh) and the Users page's TanStack queries, which a
 * refresh never touches. Both have to go, or the Users list keeps showing the account as it was.
 */
export function useAccountChanged() {
  const router = useRouter();
  const queryClient = useQueryClient();
  return useCallback(() => {
    void invalidateAccountLists(queryClient);
    router.refresh();
  }, [router, queryClient]);
}
