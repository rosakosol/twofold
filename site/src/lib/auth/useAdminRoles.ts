"use client";

import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

export interface AdminRoles {
  content: boolean;
  support: boolean;
  billing: boolean;
  /** On the admin roster at all, even at aal1 where the three above are all false once the database
   *  enforces MFA. For showing the door to the console and nothing else. */
  member: boolean;
}

const NONE: AdminRoles = { content: false, support: false, billing: false, member: false };

/**
 * Every admin role the session holds, in one request.
 *
 * This replaces three hooks that each waited on `useUser()` before firing — `auth.getUser()`, then
 * three separate RPCs, four round trips to decide which nav tabs to show. The bar rendered empty
 * and then assembled itself a tab at a time.
 *
 * Deliberately NOT gated on `enabled: !!user`. `my_admin_roles()` keys off `auth.uid()` and
 * answers "none" for an anonymous caller rather than raising, so there is nothing to wait for:
 * asking immediately is safe, and that is the round trip the waterfall was made of.
 *
 * Cached for the session. A role changes when somebody edits `feedback_admins` by hand, which is
 * not something to refetch on every window focus — and the pages and RPCs behind them enforce the
 * real thing anyway, so a stale answer here shows or hides a tab, never grants anything.
 */
export function useAdminRoles(): AdminRoles {
  return useAdminRolesState().roles;
}

/** The same, plus whether the answer is in yet, for a caller that must not act on the
 *  all-false placeholder (a "you can't edit this" note would flash for every admin). */
export function useAdminRolesState(): { roles: AdminRoles; isLoaded: boolean } {
  const { data } = useQuery({
    queryKey: ["auth", "my_admin_roles"],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("my_admin_roles");
      if (error) return NONE;
      return (data ?? NONE) as unknown as AdminRoles;
    },
    staleTime: 5 * 60 * 1000,
    refetchOnWindowFocus: false,
  });
  return { roles: data ?? NONE, isLoaded: data !== undefined };
}
