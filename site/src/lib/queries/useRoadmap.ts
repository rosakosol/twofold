import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { queryKeys } from "@/lib/queries/queryKeys";
import { fetchAuthorProfiles } from "@/lib/queries/authorProfiles";
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
  // Only display_name, not the full PublicAuthorProfile shape — RequestsList's
  // FeatureCard is the only consumer (RoadmapColumn itself never renders author).
  author: { display_name: string } | null;
}

export function useRoadmap() {
  return useQuery({
    queryKey: queryKeys.roadmap(),
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("feature_requests")
        .select("id, title, description, category, status, upvote_count, comment_count, created_at, author_id")
        .in("status", ROADMAP_STATUSES)
        .is("merged_into", null)
        .order("upvote_count", { ascending: false });
      if (error) throw error;

      const rows = data as unknown as (Omit<RoadmapItem, "author"> & { author_id: string | null })[];
      const authors = await fetchAuthorProfiles(supabase, rows.map((row) => row.author_id));

      const byStatus = new Map<FeatureStatus, RoadmapItem[]>(ROADMAP_STATUSES.map((status) => [status, []]));
      for (const { author_id, ...row } of rows) {
        const author = author_id ? authors.get(author_id) : undefined;
        byStatus.get(row.status)?.push({ ...row, author: author ? { display_name: author.display_name } : null });
      }
      return byStatus;
    },
  });
}
