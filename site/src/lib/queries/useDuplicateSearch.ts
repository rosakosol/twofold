import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { queryKeys } from "@/lib/queries/queryKeys";

export interface SimilarFeature {
  id: string;
  title: string;
  slug: string;
  upvote_count: number;
  status: string;
  similarity: number;
}

/** Backed by the search_similar_feature_requests() RPC (trigram similarity on title) —
 * see supabase/migrations/20260719000900_search_similar_feature_requests.sql. Caller
 * is expected to debounce `query` itself (see FeatureSubmitDialog). */
export function useDuplicateSearch(query: string) {
  const trimmed = query.trim();

  return useQuery({
    queryKey: queryKeys.duplicateSearch(trimmed),
    enabled: trimmed.length >= 3,
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("search_similar_feature_requests", {
        query: trimmed,
        match_limit: 5,
      });
      if (error) throw error;
      return data as SimilarFeature[];
    },
  });
}
