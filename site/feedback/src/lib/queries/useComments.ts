import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { queryKeys } from "@/lib/queries/queryKeys";

export interface Comment {
  id: string;
  feature_id: string;
  user_id: string;
  body: string;
  created_at: string;
  updated_at: string;
  author: { id: string; display_name: string; avatar_path: string | null } | null;
}

export function useComments(featureId: string) {
  return useQuery({
    queryKey: queryKeys.comments(featureId),
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("feature_comments")
        .select(
          `id, feature_id, user_id, body, created_at, updated_at,
           author:feedback_public_profiles!feature_comments_user_id_fkey(id, display_name, avatar_path)`
        )
        .eq("feature_id", featureId)
        .order("created_at", { ascending: true });
      if (error) throw error;
      return data as unknown as Comment[];
    },
  });
}

export function useCreateComment(featureId: string) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ body, userId }: { body: string; userId: string }) => {
      const supabase = createClient();
      const { error } = await supabase
        .from("feature_comments")
        .insert({ feature_id: featureId, user_id: userId, body });
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.comments(featureId) });
      queryClient.invalidateQueries({ queryKey: queryKeys.feature(featureId) });
      queryClient.invalidateQueries({ queryKey: ["features", "list"] });
    },
  });
}

export function useDeleteComment(featureId: string) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (commentId: string) => {
      const supabase = createClient();
      const { error } = await supabase.from("feature_comments").delete().eq("id", commentId);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.comments(featureId) });
      queryClient.invalidateQueries({ queryKey: ["features", "list"] });
    },
  });
}
