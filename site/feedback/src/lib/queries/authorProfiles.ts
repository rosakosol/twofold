import type { SupabaseClient } from "@supabase/supabase-js";

export interface PublicAuthorProfile {
  id: string;
  display_name: string;
  avatar_path: string | null;
}

/** Batch-fetches public-safe author profiles via the get_feedback_public_profiles
 * security-definer function — replaces the old feedback_public_profiles view (which
 * Supabase's Security Advisor flagged as a "Security Definer View"). PostgREST can
 * embed a view the same way it embeds a table via a foreign key, but not a function,
 * so callers select a bare author_id and merge this map in afterward instead of
 * embedding the profile inline. */
export async function fetchAuthorProfiles(
  supabase: SupabaseClient,
  ids: (string | null | undefined)[]
): Promise<Map<string, PublicAuthorProfile>> {
  const unique = [...new Set(ids.filter((id): id is string => !!id))];
  if (unique.length === 0) return new Map();

  const { data, error } = await supabase.rpc("get_feedback_public_profiles", { profile_ids: unique });
  if (error) throw error;

  return new Map((data ?? []).map((row: PublicAuthorProfile) => [row.id, row]));
}
