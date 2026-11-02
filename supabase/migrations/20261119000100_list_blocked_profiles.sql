-- ---------------------------------------------------------------------------
-- Who have I blocked?
-- ---------------------------------------------------------------------------
--
-- 20261023000000 added blocking, and `unblock_profile` with it, and nothing in the app has ever
-- been able to call the second one: there was no list to call it from. A block was permanent the
-- moment it was made, which is not what the confirmation said and not what anyone expects of a
-- block. The person you blocked in a bad week stayed blocked, with no screen that even admitted it.
--
-- The list cannot be read straight from `blocked_profiles` and joined to `profiles` by the client,
-- because the blocked person's profile is not readable by the blocker: profiles RLS lets you read
-- yourself and your partner, and a blocked person is, by construction, not your partner. So this
-- is security definer, and returns only what the screen needs — the id to unblock with, and a
-- first name to recognise them by. No avatar: a list of faces you chose never to see again is not
-- a kindness, and the name is enough to find the one you mean.
--
-- Only the caller's own blocks, in one direction. Being blocked is never something the blocked
-- person can read, here or anywhere (see 20261023000000's policies).

create or replace function public.list_blocked_profiles()
returns table (profile_id uuid, first_name text, blocked_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select b.blocked_id, coalesce(p.first_name, ''), b.created_at
  from public.blocked_profiles b
  left join public.profiles p on p.id = b.blocked_id
  where b.blocker_id = auth.uid()
  order by b.created_at desc;
$$;

comment on function public.list_blocked_profiles() is
  'The people the caller has blocked, newest first, with the first name to show them by. Never '
  'the other direction: who has blocked you is not something you can ask.';

revoke all on function public.list_blocked_profiles() from public, anon;
grant execute on function public.list_blocked_profiles() to authenticated;
