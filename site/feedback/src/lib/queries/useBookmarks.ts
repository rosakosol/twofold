import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { queryKeys } from "@/lib/queries/queryKeys";
import type { FeatureListItem } from "@/lib/queries/useFeatureList";

/** The set of feature ids the current user has bookmarked — same cheap single-round-trip
 * shape as useMyVoteIds, so any card can answer "is this bookmarked?" without a
 * per-card query. */
export function useMyBookmarkIds(userId: string | undefined) {
  return useQuery({
    queryKey: queryKeys.myBookmarks(userId),
    enabled: !!userId,
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("feature_bookmarks")
        .select("feature_id")
        .eq("user_id", userId!);
      if (error) throw error;
      return new Set(data.map((row) => row.feature_id));
    },
  });
}

/** Full bookmarked requests for the signed-in user, newest-bookmarked first — a
 * personal saved list, small enough per-user that it doesn't need pagination. */
export function useBookmarkedFeatures(userId: string | undefined) {
  return useQuery({
    queryKey: ["features", "bookmarked", userId],
    enabled: !!userId,
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("feature_bookmarks")
        .select(
          `feature:feature_requests!feature_bookmarks_feature_id_fkey(
            id, title, slug, description, category, status, upvote_count, comment_count,
            is_pinned, merged_into, created_at, updated_at, author_id,
            author:feedback_public_profiles!feature_requests_author_id_fkey(id, display_name, avatar_path)
          )`
        )
        .eq("user_id", userId!)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return (data ?? [])
        .map((row) => row.feature as unknown as FeatureListItem | null)
        .filter((feature): feature is FeatureListItem => !!feature);
    },
  });
}

interface BookmarkVars {
  featureId: string;
  userId: string;
  isCurrentlyBookmarked: boolean;
}

export function useToggleBookmark() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ featureId, userId, isCurrentlyBookmarked }: BookmarkVars) => {
      const supabase = createClient();
      if (isCurrentlyBookmarked) {
        const { error } = await supabase
          .from("feature_bookmarks")
          .delete()
          .eq("feature_id", featureId)
          .eq("user_id", userId);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from("feature_bookmarks")
          .insert({ feature_id: featureId, user_id: userId });
        if (error) throw error;
      }
    },
    onMutate: async ({ featureId, userId, isCurrentlyBookmarked }) => {
      await queryClient.cancelQueries({ queryKey: queryKeys.myBookmarks(userId) });

      const previousBookmarkIds = queryClient.getQueryData<Set<string>>(queryKeys.myBookmarks(userId));

      queryClient.setQueryData<Set<string>>(queryKeys.myBookmarks(userId), (prev) => {
        const next = new Set(prev ?? []);
        if (isCurrentlyBookmarked) next.delete(featureId);
        else next.add(featureId);
        return next;
      });

      return { previousBookmarkIds };
    },
    onError: (_err, { userId }, context) => {
      if (context?.previousBookmarkIds) {
        queryClient.setQueryData(queryKeys.myBookmarks(userId), context.previousBookmarkIds);
      }
    },
    onSettled: (_data, _error, { userId }) => {
      queryClient.invalidateQueries({ queryKey: queryKeys.myBookmarks(userId) });
      queryClient.invalidateQueries({ queryKey: ["features", "bookmarked", userId] });
    },
  });
}
