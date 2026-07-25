-- Fixes two problems with `device_push_tokens` RLS, both stemming from the fact that an APNs
-- token identifies a *device*, not an account, while the policies in the flight-tracking
-- migration assumed a token belongs to whoever first registered it.
--
-- 1. Signing into a second account on a device that had already registered its token failed
--    outright: `BackendService.registerDeviceToken` upserts on the `apns_token` unique
--    constraint, and on the DO UPDATE path Postgres checks the existing row against the UPDATE
--    policy's USING clause — which was `profile_id = auth.uid()`, i.e. the *previous* owner.
--    The row isn't visible to the new user, so the whole statement failed with 42501
--    "new row violates row-level security policy" and that device silently stopped receiving
--    pushes for the account now signed in.
--
-- 2. The UPDATE policy had no WITH CHECK, so the implicit check fell back to USING — which
--    constrains the OLD row, not the new one. A user could therefore rewrite their own row's
--    `profile_id` to somebody else's and start receiving that person's notifications on their
--    own device. Adding the explicit WITH CHECK closes that.

drop policy "device_push_tokens_update_own" on public.device_push_tokens;

create policy "device_push_tokens_update_own" on public.device_push_tokens
  for update using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- Legitimate device hand-off (problem 1) goes through a narrow security-definer RPC rather than
-- by loosening the UPDATE policy. Widening USING to `true` would let a caller claim a token they
-- can name, but PostgREST also permits an unfiltered PATCH — so `true` would make a single
-- request that reassigns *every* token in the table to the caller possible. Here the only row
-- reachable is the one whose exact token the caller supplied, which they can only know by
-- holding the device APNs issued it to.
create function public.register_device_push_token(
  p_apns_token text,
  p_environment text default 'production'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid := auth.uid();
begin
  if v_profile_id is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.device_push_tokens (profile_id, apns_token, environment, last_seen_at)
  values (v_profile_id, p_apns_token, p_environment, now())
  on conflict (apns_token) do update
    set profile_id = excluded.profile_id,
        environment = excluded.environment,
        last_seen_at = excluded.last_seen_at;
end;
$$;

grant execute on function public.register_device_push_token(text, text) to authenticated;
