import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { queryKeys } from "@/lib/queries/queryKeys";

interface WithVotable {
  id: string;
  upvote_count: number;
}

function isVotable(value: unknown): value is WithVotable {
  return (
    typeof value === "object" &&
    value !== null &&
    "id" in value &&
    "upvote_count" in value &&
    typeof (value as WithVotable).upvote_count === "number"
  );
}

/** Bumps upvote_count for `featureId` wherever it appears in a cached "features" query,
 * whatever shape that query happens to be: a flat array (useRoadmap's per-status
 * buckets), or the {pages: [{items,...}]} shape useInfiniteQuery wraps list pages in
 * (useInfiniteFeatureList). Recursing structurally means every current and future
 * "features" query shape gets optimistic updates for free, without listing cache
 * shapes out by hand here. */
function bumpVoteCount(data: unknown, featureId: string, delta: number): unknown {
  if (!data) return data;

  if (isVotable(data)) {
    return data.id === featureId ? { ...data, upvote_count: data.upvote_count + delta } : data;
  }

  if (Array.isArray(data)) {
    return data.map((item) => bumpVoteCount(item, featureId, delta));
  }

  // useRoadmap caches its data as a Map<status, items[]> rather than a plain array/
  // object — Map entries aren't enumerable object properties, so the generic object
  // branch below would silently skip them without this explicit case.
  if (data instanceof Map) {
    const next = new Map(data);
    for (const [key, value] of next) {
      next.set(key, bumpVoteCount(value, featureId, delta));
    }
    return next;
  }

  if (typeof data === "object") {
    const obj = data as Record<string, unknown>;
    if (Array.isArray(obj.items)) {
      return { ...obj, items: bumpVoteCount(obj.items, featureId, delta) };
    }
    if (Array.isArray(obj.pages)) {
      return { ...obj, pages: bumpVoteCount(obj.pages, featureId, delta) };
    }
  }

  return data;
}

/** The set of feature ids the current user has voted on — cheap, single round trip,
 * lets any FeatureCard answer "have I voted on this?" without a per-card query. */
export function useMyVoteIds(userId: string | undefined) {
  return useQuery({
    queryKey: queryKeys.myVotes(userId),
    enabled: !!userId,
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("feature_votes")
        .select("feature_id")
        .eq("user_id", userId!);
      if (error) throw error;
      return new Set(data.map((row) => row.feature_id));
    },
  });
}

interface VoteVars {
  featureId: string;
  userId: string;
  isCurrentlyVoted: boolean;
}

/** Toggles a vote with an optimistic update to both the vote-id set and every cached
 * feature-list page's upvote_count — rolled back on failure. */
export function useVote() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ featureId, userId, isCurrentlyVoted }: VoteVars) => {
      const supabase = createClient();
      if (isCurrentlyVoted) {
        const { error } = await supabase
          .from("feature_votes")
          .delete()
          .eq("feature_id", featureId)
          .eq("user_id", userId);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from("feature_votes")
          .insert({ feature_id: featureId, user_id: userId });
        if (error) throw error;
      }
    },
    onMutate: async ({ featureId, userId, isCurrentlyVoted }) => {
      await queryClient.cancelQueries({ queryKey: queryKeys.myVotes(userId) });
      await queryClient.cancelQueries({ queryKey: ["features"] });

      const previousVoteIds = queryClient.getQueryData<Set<string>>(queryKeys.myVotes(userId));
      const previousLists = queryClient.getQueriesData({ queryKey: ["features"] });

      queryClient.setQueryData<Set<string>>(queryKeys.myVotes(userId), (prev) => {
        const next = new Set(prev ?? []);
        if (isCurrentlyVoted) next.delete(featureId);
        else next.add(featureId);
        return next;
      });

      const delta = isCurrentlyVoted ? -1 : 1;
      queryClient.setQueriesData({ queryKey: ["features"] }, (prev: unknown) =>
        bumpVoteCount(prev, featureId, delta)
      );

      return { previousVoteIds, previousLists };
    },
    onError: (_err, { userId }, context) => {
      if (context?.previousVoteIds) {
        queryClient.setQueryData(queryKeys.myVotes(userId), context.previousVoteIds);
      }
      context?.previousLists?.forEach(([key, data]) => {
        queryClient.setQueryData(key, data);
      });
    },
    onSettled: (_data, _error, { userId }) => {
      queryClient.invalidateQueries({ queryKey: queryKeys.myVotes(userId) });
      queryClient.invalidateQueries({ queryKey: ["features"] });
    },
  });
}
