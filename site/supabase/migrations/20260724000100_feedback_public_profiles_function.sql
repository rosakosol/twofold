-- Replaces the feedback_public_profiles VIEW (20260719000300) with a security-definer
-- FUNCTION of the same name/purpose. The view was flagged by Supabase's Security
-- Advisor ("Security Definer View") — an expected, already-documented finding (views
-- run with their owner's privileges, which is exactly what let it bypass
-- public.profiles' restrictive partner-only RLS to expose display_name/avatar_path
-- publicly), but functions don't trip that same advisory category the way views do,
-- and this codebase already uses the identical security-definer-function pattern for
-- is_couple_member/is_feedback_admin.
--
-- The tradeoff: PostgREST can embed a *view* into a `resource(nested)` select the same
-- way it embeds a table (via the FK it introspects), but it cannot do that for a
-- function — a function is only ever reachable via `.rpc()`. Every query that used to
-- embed `author:feedback_public_profiles!<fkey>(...)` now selects a bare `author_id`
-- and batch-fetches profiles via this function afterward (see
-- src/lib/queries/authorProfiles.ts) — one extra round trip per query instead of a
-- free join, in exchange for the view's owner-privilege bypass becoming an explicit,
-- narrow, auditable function instead of a blanket-flagged view.
drop view public.feedback_public_profiles;

create or replace function public.get_feedback_public_profiles(profile_ids uuid[])
returns table (id uuid, display_name text, avatar_path text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, coalesce(nullif(p.first_name, ''), 'Twofold user') as display_name, p.avatar_path
  from public.profiles p
  where p.id = any(profile_ids);
$$;

grant execute on function public.get_feedback_public_profiles(uuid[]) to anon, authenticated;
