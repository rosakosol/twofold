-- ---------------------------------------------------------------------------
-- device_push_tokens: a device silent for 90 days is forgotten, a live one never is
-- ---------------------------------------------------------------------------
--
-- See 20261122000000_prune_stale_device_push_tokens.sql. The assertions that matter most are the
-- ones about refreshed rows. A prune that removed a device the app had just re-registered would
-- silently stop that person's notifications until their next launch, so this checks a stale row
-- that is refreshed through the RPC the app calls, through a plain update (the path older builds
-- took), and a row just inside the 90 days.

begin;
select plan(11);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-7777-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@token-prune.test', 'x', now(), now(), now()),
  ('aaaaaaaa-7777-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@token-prune.test', 'x', now(), now(), now());

insert into public.device_push_tokens (profile_id, apns_token, environment, created_at, last_seen_at) values
  ('aaaaaaaa-7777-0000-0000-000000000001', 'prune-test-long-dead',       'production', now() - interval '400 days', now() - interval '200 days'),
  ('aaaaaaaa-7777-0000-0000-000000000001', 'prune-test-just-past',       'production', now() - interval '400 days', now() - interval '90 days 1 hour'),
  ('aaaaaaaa-7777-0000-0000-000000000001', 'prune-test-just-inside',     'production', now() - interval '400 days', now() - interval '89 days 23 hours'),
  ('aaaaaaaa-7777-0000-0000-000000000001', 'prune-test-fresh',           'sandbox',    now(),                       now()),
  ('aaaaaaaa-7777-0000-0000-000000000001', 'prune-test-rpc-refreshed',   'production', now() - interval '400 days', now() - interval '300 days'),
  ('aaaaaaaa-7777-0000-0000-000000000001', 'prune-test-patch-refreshed', 'production', now() - interval '400 days', now() - interval '300 days');

-- What the app does on every launch: registers the token it was just handed, here from a second
-- account signing in on the same device, which reassigns the row.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-7777-0000-0000-000000000002', true);
select public.register_device_push_token('prune-test-rpc-refreshed', 'production');
reset role;

-- What builds from before register_device_push_token did: a direct upsert that names only the
-- token, profile and environment. It never set last_seen_at, so without the trigger this row
-- would still look 300 days stale.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-7777-0000-0000-000000000001', true);
update public.device_push_tokens set environment = 'production' where apns_token = 'prune-test-patch-refreshed';
reset role;

select ok(
  (select last_seen_at > now() - interval '1 minute' from public.device_push_tokens where apns_token = 'prune-test-patch-refreshed'),
  'any update to a token stamps it as seen, whoever wrote it and whatever columns they named'
);

select is(
  private.prune_stale_device_push_tokens(),
  2,
  'the prune reports how many tokens it removed'
);

select ok(
  not exists (select 1 from public.device_push_tokens where apns_token = 'prune-test-long-dead'),
  'a token unseen for 200 days is removed'
);

select ok(
  not exists (select 1 from public.device_push_tokens where apns_token = 'prune-test-just-past'),
  'and one an hour past 90 days'
);

select ok(
  exists (select 1 from public.device_push_tokens where apns_token = 'prune-test-just-inside'),
  'a token an hour short of 90 days is kept'
);

select ok(
  exists (select 1 from public.device_push_tokens where apns_token = 'prune-test-fresh'),
  'a token seen today is kept'
);

select ok(
  exists (select 1 from public.device_push_tokens
    where apns_token = 'prune-test-rpc-refreshed' and profile_id = 'aaaaaaaa-7777-0000-0000-000000000002'),
  'a long-stale token re-registered through the app''s RPC is kept, under its new owner'
);

select ok(
  exists (select 1 from public.device_push_tokens where apns_token = 'prune-test-patch-refreshed'),
  'a long-stale token refreshed by a direct update is kept'
);

-- A pruned device that is still installed comes back on its next launch: the RPC inserts a fresh
-- row rather than needing the old one.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-7777-0000-0000-000000000001', true);
select public.register_device_push_token('prune-test-long-dead', 'production');
reset role;

select ok(
  exists (select 1 from public.device_push_tokens
    where apns_token = 'prune-test-long-dead' and last_seen_at > now() - interval '1 minute'),
  'a pruned device that launches again is registered afresh'
);

-- ---------------------------------------------------------------------------
-- Cron's, and nobody else's
-- ---------------------------------------------------------------------------

select is(
  (select command from cron.job where jobname = 'prune-stale-device-push-tokens'),
  'select private.prune_stale_device_push_tokens();',
  'the prune is scheduled'
);

set local role authenticated;

select throws_ok(
  $$ select private.prune_stale_device_push_tokens() $$,
  '42501',
  NULL,
  'a signed-in client cannot run the prune'
);

reset role;

select * from finish();
rollback;
