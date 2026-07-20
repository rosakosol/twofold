import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

const VOTER_PREVIEW_LIMIT = 6;

export interface FeatureVoter {
  id: string;
  display_name: string;
  avatar_path: string | null;
}

/** Most recent voters on a request, for the avatar-stack social-proof strip — capped at
 * VOTER_PREVIEW_LIMIT since this is a preview, not a full voter list. */
export function useFeatureVoters(featureId: string, totalVotes: number) {
  return useQuery({
    queryKey: ["features", featureId, "voters"],
    enabled: totalVotes > 0,
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("feature_votes")
        .select("voter:feedback_public_profiles!feature_votes_user_id_fkey(id, display_name, avatar_path)")
        .eq("feature_id", featureId)
        .order("created_at", { ascending: false })
        .limit(VOTER_PREVIEW_LIMIT);
      if (error) throw error;

      return (data ?? [])
        .map((row) => row.voter as unknown as FeatureVoter | null)
        .filter((voter): voter is FeatureVoter => !!voter);
    },
  });
}
