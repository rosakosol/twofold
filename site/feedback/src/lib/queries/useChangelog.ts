import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { queryKeys } from "@/lib/queries/queryKeys";

export interface ChangelogEntry {
  id: string;
  body: string;
  created_at: string;
  feature: { id: string; title: string; slug: string; status: string } | null;
  author: { id: string; display_name: string; avatar_path: string | null } | null;
}

export function useChangelog() {
  return useQuery({
    queryKey: queryKeys.changelog(),
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("developer_updates")
        .select(
          `id, body, created_at,
           feature:feature_requests!developer_updates_feature_id_fkey(id, title, slug, status),
           author:feedback_public_profiles!developer_updates_author_id_fkey(id, display_name, avatar_path)`
        )
        .order("created_at", { ascending: false });
      if (error) throw error;
      return data as unknown as ChangelogEntry[];
    },
  });
}
