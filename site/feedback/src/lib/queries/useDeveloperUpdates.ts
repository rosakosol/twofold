import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

export interface DeveloperUpdate {
  id: string;
  feature_id: string;
  author_id: string | null;
  body: string;
  created_at: string;
  author: { id: string; display_name: string; avatar_path: string | null } | null;
}

export function useDeveloperUpdates(featureId: string) {
  return useQuery({
    queryKey: ["features", featureId, "developer-updates"],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("developer_updates")
        .select(
          `id, feature_id, author_id, body, created_at,
           author:feedback_public_profiles!developer_updates_author_id_fkey(id, display_name, avatar_path)`
        )
        .eq("feature_id", featureId)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return data as unknown as DeveloperUpdate[];
    },
  });
}
