import { useMutation, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import type { Database } from "@/lib/db/types";
import type { ContentTypeKey, GameDeck } from "@/lib/games/contentTypes";

type ContentInsert<T extends ContentTypeKey> = Database["public"]["Tables"][T]["Insert"];
type ContentUpdate<T extends ContentTypeKey> = Database["public"]["Tables"][T]["Update"];

function invalidateContent(queryClient: ReturnType<typeof useQueryClient>, table: ContentTypeKey) {
  queryClient.invalidateQueries({ queryKey: ["admin", table] });
  // Deck question_count is server-maintained by trigger, but the client-side cache of
  // game_decks doesn't know that happened — refetch it too so counts shown in the UI
  // don't go stale after an add/edit/delete.
  queryClient.invalidateQueries({ queryKey: ["admin", "game_decks"] });
}

export function useCreateContent<T extends ContentTypeKey>(table: T) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (row: ContentInsert<T>) => {
      const supabase = createClient();
      const { error } = await supabase.from(table).insert(row as never);
      if (error) throw error;
    },
    onSuccess: () => invalidateContent(queryClient, table),
  });
}

export function useUpdateContent<T extends ContentTypeKey>(table: T) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, patch }: { id: string; patch: ContentUpdate<T> }) => {
      const supabase = createClient();
      const { error } = await supabase.from(table).update(patch as never).eq("id" as never, id);
      if (error) throw error;
    },
    onSuccess: () => invalidateContent(queryClient, table),
  });
}

export function useDeleteContent(table: ContentTypeKey) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const supabase = createClient();
      const { error } = await supabase.from(table).delete().eq("id" as never, id);
      if (error) throw error;
    },
    onSuccess: () => invalidateContent(queryClient, table),
  });
}

export function useCreateDeck() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (row: Database["public"]["Tables"]["game_decks"]["Insert"]) => {
      const supabase = createClient();
      const { error } = await supabase.from("game_decks").insert(row);
      if (error) throw error;
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["admin", "game_decks"] }),
  });
}

export function useUpdateDeck() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, patch }: { id: string; patch: Database["public"]["Tables"]["game_decks"]["Update"] }) => {
      const supabase = createClient();
      const { error } = await supabase.from("game_decks").update(patch).eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["admin", "game_decks"] }),
  });
}

export function useDeleteDeck() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const supabase = createClient();
      const { error } = await supabase.from("game_decks").delete().eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["admin", "game_decks"] }),
  });
}

export type { GameDeck };
