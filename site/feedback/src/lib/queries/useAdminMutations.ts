import { useMutation, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { queryKeys } from "@/lib/queries/queryKeys";
import type { FeatureCategory, FeatureStatus } from "@/lib/utils/constants";

function invalidateFeatureQueries(queryClient: ReturnType<typeof useQueryClient>) {
  queryClient.invalidateQueries({ queryKey: ["admin"] });
  queryClient.invalidateQueries({ queryKey: ["features"] });
}

export function useUpdateFeatureStatus() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, status }: { id: string; status: FeatureStatus }) => {
      const supabase = createClient();
      const { error } = await supabase.from("feature_requests").update({ status }).eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => invalidateFeatureQueries(queryClient),
  });
}

export function useTogglePin() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, isPinned }: { id: string; isPinned: boolean }) => {
      const supabase = createClient();
      const { error } = await supabase
        .from("feature_requests")
        .update({ is_pinned: !isPinned })
        .eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => invalidateFeatureQueries(queryClient),
  });
}

export function useDeleteFeature() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const supabase = createClient();
      const { error } = await supabase.from("feature_requests").delete().eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => invalidateFeatureQueries(queryClient),
  });
}

export function useMergeFeatures() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ sourceId, targetId }: { sourceId: string; targetId: string }) => {
      const supabase = createClient();
      const { error } = await supabase.rpc("merge_feature_requests", {
        source_id: sourceId,
        target_id: targetId,
      });
      if (error) throw error;
    },
    onSuccess: () => invalidateFeatureQueries(queryClient),
  });
}

export function useUpdateFeatureDetails(id: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (patch: { title: string; description: string; category: FeatureCategory }) => {
      const supabase = createClient();
      const { error } = await supabase.from("feature_requests").update(patch).eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => invalidateFeatureQueries(queryClient),
  });
}

export function usePostDeveloperUpdate(featureId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ body, authorId }: { body: string; authorId: string }) => {
      const supabase = createClient();
      const { error } = await supabase
        .from("developer_updates")
        .insert({ feature_id: featureId, author_id: authorId, body });
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["features", featureId, "developer-updates"] });
      queryClient.invalidateQueries({ queryKey: queryKeys.changelog() });
    },
  });
}
