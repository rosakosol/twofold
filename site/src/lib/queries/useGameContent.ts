import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import type { ContentRow, ContentTypeKey, GameDeck, GameType } from "@/lib/games/contentTypes";

export function useGameDecks(gameType?: GameType) {
  return useQuery({
    queryKey: ["admin", "game_decks", gameType ?? "all"],
    queryFn: async () => {
      const supabase = createClient();
      let query = supabase.from("game_decks").select("*").order("sort_order", { ascending: true });
      if (gameType) query = query.eq("game_type", gameType);
      const { data, error } = await query;
      if (error) throw error;
      return data as GameDeck[];
    },
  });
}

export function useGameDeck(id: string) {
  return useQuery({
    queryKey: ["admin", "game_decks", "one", id],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase.from("game_decks").select("*").eq("id", id).single();
      if (error) throw error;
      return data as GameDeck;
    },
  });
}

export function useGameContentList(table: ContentTypeKey) {
  return useQuery({
    queryKey: ["admin", table],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase.from(table).select("*").order("category", { ascending: true });
      if (error) throw error;
      return data as unknown as ContentRow[];
    },
  });
}

/** Just `tier` — used to compute the games-hub summary stats without pulling every entry's
 * full text/options/etc. across all game types on one page load. */
export function useGameContentTiers(table: ContentTypeKey) {
  return useQuery({
    queryKey: ["admin", table, "tiers"],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase.from(table).select("tier");
      if (error) throw error;
      return data as { tier: string }[];
    },
  });
}
