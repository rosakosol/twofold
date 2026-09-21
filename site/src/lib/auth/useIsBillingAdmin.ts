"use client";

import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { useUser } from "@/lib/auth/useUser";

/** Whether the signed-in user holds the `billing` role — used to decide whether the console's nav
 * shows the Usage tab at all. The page and the RPCs behind it enforce this themselves; hiding the
 * link is so a content admin is not shown a door that refuses them. */
export function useIsBillingAdmin(): boolean {
  const { user } = useUser();
  const { data } = useQuery({
    queryKey: ["auth", "is_billing_admin", user?.id ?? null],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("is_billing_admin");
      if (error) return false;
      return data === true;
    },
    enabled: !!user,
  });
  return data === true;
}
