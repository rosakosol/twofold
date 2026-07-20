import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { queryKeys } from "@/lib/queries/queryKeys";
import { FEATURE_DETAIL_SELECT, type FeatureDetail } from "@/lib/queries/useFeature";
import type { FeatureStatus } from "@/lib/utils/constants";

export interface AdminFeatureFilters {
  status?: FeatureStatus;
  search?: string;
  sort?: "popularity" | "newest";
}

/** Unlike the public board's useFeatureList, this deliberately does NOT filter out
 * merged requests — admins need to see (and un-merge, by re-pointing manually if ever
 * needed) everything. */
export function useAdminFeatureList(filters: AdminFeatureFilters) {
  return useQuery({
    queryKey: queryKeys.adminFeatureList(filters),
    queryFn: async () => {
      const supabase = createClient();
      let query = supabase.from("feature_requests").select(FEATURE_DETAIL_SELECT);

      if (filters.status) query = query.eq("status", filters.status);
      if (filters.search) query = query.ilike("title", `%${filters.search}%`);

      query = query.order("is_pinned", { ascending: false });
      query =
        filters.sort === "popularity"
          ? query.order("upvote_count", { ascending: false })
          : query.order("created_at", { ascending: false });

      const { data, error } = await query;
      if (error) throw error;
      return data as unknown as FeatureDetail[];
    },
  });
}

export function useAdminFeature(id: string) {
  return useQuery({
    queryKey: ["admin", "feature", id],
    enabled: !!id,
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("feature_requests")
        .select(FEATURE_DETAIL_SELECT)
        .eq("id", id)
        .single();
      if (error) throw error;
      return data as unknown as FeatureDetail;
    },
  });
}
