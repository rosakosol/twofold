-- Two things readable without being anybody: a private avatar, and whether a given account is an
-- admin.
--
-- ---------------------------------------------------------------------------
-- 1. avatars_select_pending_inviter
-- ---------------------------------------------------------------------------
--
-- From 20260901001000, on `storage.objects`, for role PUBLIC:
--
--   using (bucket_id = 'avatars' and exists (
--     select 1 from public.invite_codes
--     where inviter_id = (storage.foldername(name))[1]::uuid
--       and status = 'pending' and expires_at > now()))
--
-- No `auth.uid()` anywhere, and `anon` holds SELECT on `storage.objects`. Its comment justifies the
-- exception as "anyone who knows a still-pending, unexpired invite **code**", which is what
-- `get_invite_code_inviter_info(p_code)` gates on. This policy gates on knowing the inviter's
-- profile uuid instead — a different secret, and one that leaks from anywhere a profile id appears.
-- The implementation and the stated intent genuinely differ; it reads as an oversight.
--
-- It is also dead. The screen it was written for gets its avatar through
-- `BackendService.avatarSignedURL` -> `R2Storage.readURL` -> the `storage-url` function, which
-- calls `auth.getUser()` and then `can_access_storage_object`, both of which need a session. So
-- since the R2 migration this policy has protected nothing the app reads — only the originals left
-- in the legacy bucket for the soak, which it hands to anyone who asks.
--
-- Dropped rather than repaired. Repairing it would mean re-deriving "knows the code" from a path,
-- which is the thing `get_invite_code_inviter_info` already does properly.
--
-- Worth knowing separately: the pre-auth invite preview cannot show an avatar at all any more,
-- because `storage-url` refuses an anonymous caller. That is a pre-existing gap in the feature, not
-- something this migration causes, and it is the reason dropping this breaks nothing.
drop policy if exists "avatars_select_pending_inviter" on storage.objects;

-- ---------------------------------------------------------------------------
-- 2. flights_used_this_month
-- ---------------------------------------------------------------------------
--
-- `flights_used_this_month(p_couple_id uuid)` is SECURITY DEFINER, takes a couple id, checks
-- nothing about the caller, and returns that couple's flight count for the month. `anon` can call
-- it, so it answers to nobody at all.
--
-- `couple_is_subscribed` and `is_couple_active` keep their grants for a real reason — RLS policies
-- execute as the caller, so a policy referencing them needs the caller to hold EXECUTE, and nine
-- policies across six tables do. This one is referenced by **zero** policies. Its callers are
-- `flight_allowance`, `start_flight_tracking` and `admin_account_detail`, all SECURITY DEFINER, so
-- they run as the owner and are unaffected by a client losing the grant.
--
-- Deliberately not given a membership check to go with the revoke. `admin_account_detail` calls it
-- for a couple the support admin is not a member of, which is the whole point of a support console
-- — adding `is_couple_member` here would break that, and the authorisation that matters is already
-- at each caller's own first statement.
revoke all on function public.flights_used_this_month(uuid) from public, anon, authenticated;
grant execute on function public.flights_used_this_month(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 3. The four admin predicates
-- ---------------------------------------------------------------------------
--
-- `is_support_admin(check_id uuid default auth.uid())` and its three siblings are SECURITY DEFINER
-- with an `anon` grant. The defaulted path is correct and is what every caller uses. The exposure
-- is that the parameter is reachable over PostgREST, so an unauthenticated caller can name any
-- uuid and learn whether that account is an admin, and which kind.
--
-- `authenticated` keeps EXECUTE and has to: fifteen RLS policies reference these, policies execute
-- as the caller, and the console calls `rpc("is_support_admin")` directly. Only `anon` goes.
--
-- This narrows the oracle rather than closing it — a signed-in caller can still ask about a uuid
-- they already hold. Closing it properly means removing the parameter so the answer can only ever
-- be about `auth.uid()`, and that cannot be done with `create or replace`: the signature would
-- change, and dropping the old function is refused while fifteen policies depend on it. That is a
-- larger change than an unauthenticated read deserves to wait for, so it is written down in the
-- backlog rather than attempted here.
revoke all on function public.is_support_admin(uuid) from public, anon;
revoke all on function public.is_console_admin(uuid) from public, anon;
revoke all on function public.is_billing_admin(uuid) from public, anon;
revoke all on function public.is_feedback_admin(uuid) from public, anon;

grant execute on function public.is_support_admin(uuid) to authenticated, service_role;
grant execute on function public.is_console_admin(uuid) to authenticated, service_role;
grant execute on function public.is_billing_admin(uuid) to authenticated, service_role;
grant execute on function public.is_feedback_admin(uuid) to authenticated, service_role;
