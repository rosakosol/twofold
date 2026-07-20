import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { queryKeys } from "@/lib/queries/queryKeys";
import type { FeatureListItem } from "@/lib/queries/useFeatureList";
import type { FeatureCategory } from "@/lib/utils/constants";

export const FEATURE_DETAIL_SELECT = `
  id, title, slug, description, category, status, upvote_count, comment_count,
  is_pinned, merged_into, created_at, updated_at, author_id,
  author:feedback_public_profiles!feature_requests_author_id_fkey(id, display_name, avatar_path)
`;

export type FeatureDetail = FeatureListItem;

export function useFeature(slug: string, initialData?: FeatureDetail) {
  return useQuery({
    queryKey: queryKeys.feature(slug),
    initialData,
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("feature_requests")
        .select(FEATURE_DETAIL_SELECT)
        .eq("slug", slug)
        .single();
      if (error) throw error;
      return data as unknown as FeatureDetail;
    },
  });
}

/** Other open requests in the same category — a cheap, good-enough "related requests"
 * heuristic without needing embeddings/full-text ranking for a v1. */
export function useRelatedFeatures(category: FeatureCategory | undefined, excludeId: string | undefined) {
  return useQuery({
    queryKey: ["features", "related", category, excludeId],
    enabled: !!category && !!excludeId,
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("feature_requests")
        .select("id, title, slug, upvote_count, status")
        .eq("category", category!)
        .neq("id", excludeId!)
        .is("merged_into", null)
        .order("upvote_count", { ascending: false })
        .limit(5);
      if (error) throw error;
      return data;
    },
  });
}
