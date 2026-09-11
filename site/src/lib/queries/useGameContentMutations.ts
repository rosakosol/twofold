import { useMutation, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import type { Database } from "@/lib/db/types";
import { CONTENT_TYPES, type ContentTypeKey, type GameDeck } from "@/lib/games/contentTypes";

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

/** Deletes the deck and everything in it — its questions, and the sessions couples played from
 * it — in one transaction. Not a plain `.delete()` on game_decks: every deck_id is a NO ACTION
 * foreign key, so that fails the moment a deck holds a single question, which is the only state
 * a real deck is ever in. See 20261010000800_delete_game_deck.sql. */
export function useDeleteDeck() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("delete_game_deck", { p_deck_id: id });
      if (error) throw error;
      return data as unknown as { questions_deleted: number; sessions_deleted: number };
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["admin", "game_decks"] });
      // The deck's questions went with it, so every content list that could have been showing
      // them is now wrong — including the one behind the deck detail page we may be sitting on.
      for (const { key } of CONTENT_TYPES) queryClient.invalidateQueries({ queryKey: ["admin", key] });
    },
  });
}

export type { GameDeck };
