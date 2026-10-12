import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import type { ContentRow, ContentTypeKey, GameDeck, GameType, TieredContentTypeKey } from "@/lib/games/contentTypes";

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

/** PostgREST's `max_rows` (supabase/config.toml). A single select never returns more than this,
 * and says nothing when it stops short. */
const MAX_ROWS = 1000;

/** Every row, fetched in `MAX_ROWS` batches. Only for the similarity check, which has to compare
 * every entry with every other. A single select stopped at 1000, which dropped 133 daily questions
 * from both the list and the check without any sign they were missing. Lists use
 * `useGameContentPage` instead. `id` breaks ties in `category` so no row lands in two batches,
 * or in none. */
export function useGameContentList(table: ContentTypeKey) {
  return useQuery({
    queryKey: ["admin", table, "all"],
    queryFn: async () => {
      const supabase = createClient();
      const rows: ContentRow[] = [];
      for (let from = 0; ; from += MAX_ROWS) {
        const { data, error } = await supabase
          .from(table)
          .select("*")
          .order("category", { ascending: true })
          .order("id", { ascending: true })
          .range(from, from + MAX_ROWS - 1);
        if (error) throw error;
        rows.push(...(data as unknown as ContentRow[]));
        if (data.length < MAX_ROWS) return rows;
      }
    },
  });
}

/** One page of a content table, and how many rows the table holds in total. */
export function useGameContentPage(table: ContentTypeKey, page: number, pageSize: number, enabled = true) {
  return useQuery({
    enabled,
    queryKey: ["admin", table, "page", page, pageSize],
    queryFn: async () => {
      const supabase = createClient();
      const from = page * pageSize;
      const { data, error, count } = await supabase
        .from(table)
        .select("*", { count: "exact" })
        .order("category", { ascending: true })
        .order("id", { ascending: true })
        .range(from, from + pageSize - 1);
      if (error) throw error;
      return { rows: data as unknown as ContentRow[], total: count ?? 0 };
    },
    // The previous page stays put until the next one lands, rather than emptying to a skeleton.
    placeholderData: keepPreviousData,
  });
}

/** One deck's questions, filtered by the database rather than picked out of the whole table. */
export function useGameContentForDeck(table: TieredContentTypeKey, deckId: string | undefined) {
  return useQuery({
    enabled: Boolean(deckId),
    queryKey: ["admin", table, "deck", deckId],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from(table)
        .select("*")
        .eq("deck_id", deckId!)
        .order("category", { ascending: true })
        .order("id", { ascending: true });
      if (error) throw error;
      return data as unknown as ContentRow[];
    },
  });
}

/** Just `tier` — used to compute the games-hub summary stats without pulling every entry's
 * full text/options/etc. across all game types on one page load. */
export function useGameContentTiers(table: TieredContentTypeKey) {
  return useQuery({
    queryKey: ["admin", table, "tiers"],
    queryFn: async () => {
      const supabase = createClient();
      // Batched for the same reason as useGameContentList: one select stops at MAX_ROWS.
      const rows: { tier: string }[] = [];
      for (let from = 0; ; from += MAX_ROWS) {
        const { data, error } = await supabase
          .from(table)
          .select("tier")
          .order("id", { ascending: true })
          .range(from, from + MAX_ROWS - 1);
        if (error) throw error;
        rows.push(...(data as { tier: string }[]));
        if (data.length < MAX_ROWS) return rows;
      }
    },
  });
}
