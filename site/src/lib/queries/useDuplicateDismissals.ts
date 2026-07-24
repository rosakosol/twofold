import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import type { Database } from "@/lib/db/types";
import type { ContentTypeKey } from "@/lib/games/contentTypes";

export type DismissalRow = Database["public"]["Tables"]["game_content_duplicate_dismissals"]["Row"];

/** row_a_id/row_b_id are stored with the smaller id first (DB-enforced) so a pair only ever
 * has one possible dismissal row regardless of which order it's compared in. */
function orderedIds(idA: string, idB: string): [string, string] {
  return idA < idB ? [idA, idB] : [idB, idA];
}

export function dismissalKey(idA: string, idB: string): string {
  return orderedIds(idA, idB).join(":");
}

export function useDuplicateDismissals(contentType: ContentTypeKey) {
  return useQuery({
    queryKey: ["admin", "duplicate_dismissals", contentType],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("game_content_duplicate_dismissals")
        .select("*")
        .eq("content_type", contentType);
      if (error) throw error;
      return data as DismissalRow[];
    },
  });
}

export function useDismissDuplicatePair(contentType: ContentTypeKey) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ idA, idB }: { idA: string; idB: string }) => {
      const [row_a_id, row_b_id] = orderedIds(idA, idB);
      const supabase = createClient();
      const { error } = await supabase
        .from("game_content_duplicate_dismissals")
        .insert({ content_type: contentType, row_a_id, row_b_id });
      if (error) throw error;
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["admin", "duplicate_dismissals", contentType] }),
  });
}

export function useRestoreDuplicatePair(contentType: ContentTypeKey) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const supabase = createClient();
      const { error } = await supabase.from("game_content_duplicate_dismissals").delete().eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["admin", "duplicate_dismissals", contentType] }),
  });
}
