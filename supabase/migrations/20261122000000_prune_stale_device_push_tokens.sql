-- ---------------------------------------------------------------------------
-- device_push_tokens: forget devices that haven't been seen in 90 days
-- ---------------------------------------------------------------------------
--
-- Before this migration a token left the table in three ways: its owner signed out
-- (`BackendService.unregisterDeviceToken`), the account was deleted (cascade), or Apple answered
-- a push with 410 / BadDeviceToken / Unregistered and `_shared/apns.ts` retired it. Any other dead
-- device stayed forever: a phone that was wiped, sold or just never opened again, or a sandbox
-- token from a dev build. Apple doesn't reliably 410 those, and every cron fan-out (streak, birthday,
-- invite reminders) keeps paying an HTTP/2 request for each one.
--
-- ---------------------------------------------------------------------------
-- Why pruning a device that is still in use is safe
-- ---------------------------------------------------------------------------
--
-- The app calls `registerForRemoteNotifications()` in `didFinishLaunchingWithOptions` on every
-- launch (Twofold/App/PushNotificationDelegate.swift), and registers the token it gets back
-- through `register_device_push_token` (20260901001400), which upserts and sets
-- `last_seen_at = now()`. Anyone who has opened the app in the last 90 days is therefore never
-- touched, and a device pruned by mistake comes back the next time the app launches, because the
-- RPC inserts a fresh row when there is nothing to update. The cost of a wrong prune is
-- pushes missed until that launch, not a lost registration.
--
-- ---------------------------------------------------------------------------
-- Why any update counts as "seen"
-- ---------------------------------------------------------------------------
--
-- The RPC sets `last_seen_at`, but builds from before it existed upserted the table directly and
-- named only the token, profile and environment. That upsert updated the row and left
-- `last_seen_at` where it was, so a device those builds were refreshing every launch would still
-- have looked months stale. The trigger below stamps every update, so a row someone has just
-- written can never be pruned, whichever path wrote it. Nothing server-side updates this table
-- (the senders only ever delete from it), so the stamp means nothing except "a client wrote this".
--
-- A re-registration racing the prune is safe too. If the RPC's update commits first, the DELETE
-- re-checks its predicate against the updated row (READ COMMITTED) and skips it. If the DELETE
-- commits first, the RPC finds no row and inserts a fresh one.
--
-- ---------------------------------------------------------------------------
-- Schedule
-- ---------------------------------------------------------------------------
--
-- Pure SQL, like `purge-api-usage-events` (20261109000300): nothing to notify and nobody to call,
-- so none of the pg_net/Vault plumbing. Daily at 05:20, a slot nothing else uses. It stays clear of
-- the :00/:15/:30/:45 streak jobs, the :05 usage rollup and the 05:30 usage purge.
--
-- No index on `last_seen_at`: one row per device, scanned once a day.

create or replace function private.stamp_device_push_token_seen()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.last_seen_at := now();
  return new;
end;
$$;

drop trigger if exists trg_device_push_tokens_seen on public.device_push_tokens;

create trigger trg_device_push_tokens_seen
  before update on public.device_push_tokens
  for each row
  execute function private.stamp_device_push_token_seen();

-- Fixed at 90 days rather than taking an argument, so nothing that can reach this function can
-- turn it into "delete every token". Returns the number removed, which is what shows up in
-- `cron.job_run_details`.
create or replace function private.prune_stale_device_push_tokens()
returns integer
language sql
security definer
set search_path = public
as $$
  with pruned as (
    delete from public.device_push_tokens
    where last_seen_at < now() - interval '90 days'
    returning 1
  )
  select count(*)::integer from pruned;
$$;

comment on function private.prune_stale_device_push_tokens() is
  'Deletes device push tokens not registered or updated in 90 days. Runs daily from pg_cron. '
  'Safe for devices still in use: the app re-registers its token on every launch.';

-- Same as the other cron-only functions: `private` is already out of PostgREST's reach, and an
-- explicit revoke is what survives that config line changing.
revoke all on function private.prune_stale_device_push_tokens() from public, anon, authenticated;
revoke all on function private.stamp_device_push_token_seen() from public, anon, authenticated;

select cron.schedule(
  'prune-stale-device-push-tokens',
  '20 5 * * *',
  'select private.prune_stale_device_push_tokens();'
);
