-- Seven `revoke ... from public` lines that did not do what they read as doing, one of which is a
-- way for anybody holding the anon key to delete a couple's entire history.
--
-- ---------------------------------------------------------------------------
-- The mechanism
-- ---------------------------------------------------------------------------
--
-- Supabase ships `alter default privileges in schema public grant all on functions to anon,
-- authenticated`. So every `create function` in this repo hands anon and authenticated an EXECUTE
-- grant of their own, on top of the implicit one Postgres gives PUBLIC. `revoke all on function
-- ... from public` drops only the implicit grant. The explicit pair survive, and the function stays
-- callable by exactly the roles it was being locked away from.
--
-- 20261017000000 found this on `start_sudoku_session`, fixed that one function, and said the other
-- thirty-odd needed checking one at a time rather than a blanket revoke — some of the invite-code
-- lookups are reachable before sign-in on purpose. This is that check, for the subset where it
-- actually matters. Of the 29 functions whose revoke did not hold, 22 open with an `auth.uid()`
-- test and refuse an anonymous caller in their first statement; for those the grant is
-- defence-in-depth and they are left alone, exactly as that migration argued. The seven below
-- never mention `auth.uid()` at all, so the grant was the only thing there.
--
-- ---------------------------------------------------------------------------
-- purge_couple_data, which is the reason this is not a tidy-up
-- ---------------------------------------------------------------------------
--
--   create function public.purge_couple_data(p_couple_id uuid) returns void
--     language plpgsql security definer ...
--   begin
--     perform set_config('storage.allow_delete_query', 'true', true);
--     delete from storage.objects where bucket_id = 'memory-photos' and ... = p_couple_id::text;
--     ...
--     delete from public.couples where id = p_couple_id;
--   end;
--
-- No check on who is calling, and `couples` cascades to trips, memories, flights, game sessions
-- and their rounds and responses. The anon key is published — it ships inside the iOS binary and
-- in the website's JavaScript — so this was one POST away for anyone who knew a couple id. Nobody
-- has to guess one: every member knows their own, which makes it a way for one partner to destroy
-- the shared archive outright, bypassing `leave_couple`, the 90-day window and the restore path
-- that 20261005000000 made the only route to deletion.
--
-- `delete_dissolved_couple_data` is the same shape with a narrower blast radius, and
-- `list_streak_reminder_targets` returns profile ids, couple ids and partner ids for every couple
-- due a reminder, to anyone who asks.
--
-- ---------------------------------------------------------------------------
-- Why revoking does not break the callers
-- ---------------------------------------------------------------------------
--
-- None of these have a client caller: `purge_couple_data`, `delete_dissolved_couple_data` and
-- `mark_discussion_round` are only reached from other functions, `list_streak_reminder_targets`
-- and `record_flight_addition` only from edge functions holding the service key. A SECURITY
-- DEFINER function calling another runs as the definer, not as the caller's role, so the internal
-- callers are unaffected by a grant change — and pg_cron runs its jobs as postgres.
--
-- `get_invite_code_inviter_info` stays anon-callable on purpose and is deliberately absent below:
-- `JoinInviteView` shows the inviter's name on a tapped invite link, before any account exists.
-- `get_daily_streak` keeps `authenticated` and loses only `anon`.

-- Service-role only. Naming all three of public, anon and authenticated is the point of this
-- migration: any one of them left out is the hole reopening.
revoke all on function public.purge_couple_data(uuid) from public, anon, authenticated;
grant execute on function public.purge_couple_data(uuid) to service_role;

revoke all on function public.delete_dissolved_couple_data(uuid) from public, anon, authenticated;
grant execute on function public.delete_dissolved_couple_data(uuid) to service_role;

revoke all on function public.list_streak_reminder_targets() from public, anon, authenticated;
grant execute on function public.list_streak_reminder_targets() to service_role;

revoke all on function public.record_flight_addition(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.record_flight_addition(uuid, uuid, uuid) to service_role;

revoke all on function public.mark_discussion_round(uuid, text) from public, anon, authenticated;
grant execute on function public.mark_discussion_round(uuid, text) to service_role;

-- Signed-in callers only.
revoke all on function public.get_daily_streak() from public, anon;
grant execute on function public.get_daily_streak() to authenticated;

-- 20261030000000 revoked this from `public` alone and granted it to `authenticated`, intending
-- exactly the line below. Its own test asserts an anonymous caller gets 42501 and has been failing
-- since the day it was written.
revoke all on function public.can_access_storage_object(text, text, text) from public, anon;
grant execute on function public.can_access_storage_object(text, text, text) to authenticated;

comment on function public.purge_couple_data(uuid) is
  'Deletes a couple and everything cascading from it. service_role only, and it authorises '
  'nothing itself - the caller is the authorisation. Never grant this to anon or authenticated.';
