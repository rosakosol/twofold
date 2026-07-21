"use client";

import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/auth/useUser";

/** Client-side counterpart to isAdmin.ts's server-side isFeedbackAdmin() — same
 * is_feedback_admin() RPC, used to conditionally show admin-only nav links. */
export function useIsAdmin(): boolean {
  const { user } = useUser();
  const { data } = useQuery({
    queryKey: ["auth", "is_feedback_admin", user?.id ?? null],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("is_feedback_admin");
      if (error) return false;
      return data === true;
    },
    enabled: !!user,
  });
  return data === true;
}
