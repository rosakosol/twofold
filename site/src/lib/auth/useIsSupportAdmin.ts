"use client";

import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/auth/useUser";

/** Whether the signed-in user holds the `support` role — the one that may read and act on another
 * person's account. Used only to decide whether the console nav shows the Accounts tab; the pages
 * and the RPCs behind them enforce it themselves. */
export function useIsSupportAdmin(): boolean {
  const { user } = useUser();
  const { data } = useQuery({
    queryKey: ["auth", "is_support_admin", user?.id ?? null],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("is_support_admin");
      if (error) return false;
      return data === true;
    },
    enabled: !!user,
  });
  return data === true;
}
