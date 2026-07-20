import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

export function usePopularThisWeek(limit = 5) {
  return useQuery({
    queryKey: ["features", "popular-this-week", limit],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("popular_this_week", { result_limit: limit });
      if (error) throw error;
      return data;
    },
  });
}
