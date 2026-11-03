import { useMutation, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
// Updates and deletes ask for an exact count: one that RLS filters out returns no error, only 0.
import { requireChanged } from "@/lib/supabase/dbError";
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
      requireChanged(await supabase.from("feature_requests").update({ status }, { count: "exact" }).eq("id", id), "request");
    },
    onSuccess: () => invalidateFeatureQueries(queryClient),
  });
}

export function useTogglePin() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, isPinned }: { id: string; isPinned: boolean }) => {
      const supabase = createClient();
      requireChanged(
        await supabase.from("feature_requests").update({ is_pinned: !isPinned }, { count: "exact" }).eq("id", id),
        "request",
      );
    },
    onSuccess: () => invalidateFeatureQueries(queryClient),
  });
}

export function useDeleteFeature() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const supabase = createClient();
      requireChanged(await supabase.from("feature_requests").delete({ count: "exact" }).eq("id", id), "request");
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
      requireChanged(await supabase.from("feature_requests").update(patch, { count: "exact" }).eq("id", id), "request");
    },
    onSuccess: () => invalidateFeatureQueries(queryClient),
  });
}
