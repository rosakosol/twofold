import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { queryKeys } from "@/lib/queries/queryKeys";
import { ROADMAP_STATUSES, type FeatureStatus } from "@/lib/utils/constants";

export interface RoadmapItem {
  id: string;
  title: string;
  description: string | null;
  category: string;
  status: FeatureStatus;
  upvote_count: number;
  comment_count: number;
  created_at: string;
  author: { display_name: string } | null;
}

export function useRoadmap() {
  return useQuery({
    queryKey: queryKeys.roadmap(),
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("feature_requests")
        .select(
          `id, title, description, category, status, upvote_count, comment_count, created_at,
           author:feedback_public_profiles!feature_requests_author_id_fkey(display_name)`
        )
        .in("status", ROADMAP_STATUSES)
        .is("merged_into", null)
        .order("upvote_count", { ascending: false });
      if (error) throw error;

      const items = data as unknown as RoadmapItem[];
      const byStatus = new Map<FeatureStatus, RoadmapItem[]>(
        ROADMAP_STATUSES.map((status) => [status, []])
      );
      for (const item of items) {
        byStatus.get(item.status)?.push(item);
      }
      return byStatus;
    },
  });
}
