import { useInfiniteQuery, type InfiniteData } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { queryKeys, type FeatureListFilters } from "@/lib/queries/queryKeys";

export interface FeatureListItem {
  id: string;
  title: string;
  slug: string;
  description: string;
  category: string;
  status: string;
  upvote_count: number;
  comment_count: number;
  is_pinned: boolean;
  merged_into: string | null;
  created_at: string;
  updated_at: string;
  author_id: string | null;
  author: { id: string; display_name: string; avatar_path: string | null } | null;
}

const PAGE_SIZE = 20;

interface FeatureListPage {
  items: FeatureListItem[];
  total: number;
  hasMore: boolean;
}

/** Scroll-triggered loading for the main board — see the IntersectionObserver sentinel
 * in feedback/page.tsx that calls fetchNextPage() as it comes into view. */
export function useInfiniteFeatureList(filters: FeatureListFilters) {
  return useInfiniteQuery<FeatureListPage, Error, InfiniteData<FeatureListPage, number>, ReturnType<typeof queryKeys.featureList>, number>({
    queryKey: queryKeys.featureList(filters),
    initialPageParam: 0,
    getNextPageParam: (lastPage, allPages) => (lastPage.hasMore ? allPages.length : undefined),
    queryFn: async ({ pageParam }) => {
      const supabase = createClient();
      let query = supabase
        .from("feature_requests")
        .select(
          `id, title, slug, description, category, status, upvote_count, comment_count,
           is_pinned, merged_into, created_at, updated_at, author_id,
           author:feedback_public_profiles!feature_requests_author_id_fkey(id, display_name, avatar_path)`,
          { count: "exact" }
        )
        .is("merged_into", null);

      if (filters.category) query = query.eq("category", filters.category);
      if (filters.status) query = query.eq("status", filters.status);
      if (filters.search) query = query.ilike("title", `%${filters.search}%`);

      query = query.order("is_pinned", { ascending: false });
      if (filters.sort === "top") {
        query = query.order("upvote_count", { ascending: false });
      } else if (filters.sort === "new") {
        query = query.order("created_at", { ascending: false });
      } else {
        query = query.order("updated_at", { ascending: false });
      }

      const from = pageParam * PAGE_SIZE;
      const { data, error, count } = await query.range(from, from + PAGE_SIZE - 1);
      if (error) throw error;

      return {
        items: (data ?? []) as unknown as FeatureListItem[],
        total: count ?? 0,
        hasMore: (count ?? 0) > from + PAGE_SIZE,
      };
    },
  });
}
