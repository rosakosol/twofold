-- Which columns of `profiles` a signed-in client may write.
--
-- 20260915000000 turned table-level UPDATE off and granted it back column by column, enumerated
-- from the catalogue. That cannot cover columns added afterwards, and `locale` proved it: added
-- four weeks later, never granted, and because the client writes it in the same statement as
-- `timezone` it silently took that down too — both were null for every profile until
-- 20261029000400.
--
-- So this asserts the shape rather than the list: the things the client is supposed to write, the
-- things it must never write, and — the one that actually broke — the real combined statement,
-- because a per-column check would have passed on `timezone` all along while the app's own write
-- was being refused.

begin;
select plan(6);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values ('aaaaaaaa-1111-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'grants@cols.test', 'x', now(), now())
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-1111-0000-0000-00000000000a","role":"authenticated"}';

-- ---------------------------------------------------------------------------
-- What the client legitimately writes
-- ---------------------------------------------------------------------------

-- The statement `BackendService.updateDeviceContext()` actually sends. Both columns at once is the
-- whole point: Postgres refuses the statement if any one column is ungranted, so this is the only
-- assertion that would have caught the original bug.
select lives_ok(
  $$ update public.profiles set timezone = 'Australia/Melbourne', locale = 'en-AU'
     where id = 'aaaaaaaa-1111-0000-0000-00000000000a' $$,
  'the device-context write (timezone AND locale together) is allowed'
);

select lives_ok(
  $$ update public.profiles set first_name = 'Alex'
     where id = 'aaaaaaaa-1111-0000-0000-00000000000a' $$,
  'a person can rename themselves'
);

select lives_ok(
  $$ update public.profiles set setup_checklist_dismissed = true
     where id = 'aaaaaaaa-1111-0000-0000-00000000000a' $$,
  'and dismiss the setup checklist'
);

-- ---------------------------------------------------------------------------
-- What it must never write
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ update public.profiles set last_active_at = now() + interval '10 years'
     where id = 'aaaaaaaa-1111-0000-0000-00000000000a' $$,
  '42501',
  null,
  'a client cannot write last_active_at — it is the dormancy timer''s only input, and writing it would hold a dead account open forever'
);

select throws_ok(
  $$ update public.profiles set dormancy_warned_at = now() + interval '10 years'
     where id = 'aaaaaaaa-1111-0000-0000-00000000000a' $$,
  '42501',
  null,
  'nor dormancy_warned_at, which would suppress their own deletion warnings'
);

select throws_ok(
  $$ update public.profiles set subscription_active = true
     where id = 'aaaaaaaa-1111-0000-0000-00000000000a' $$,
  '42501',
  null,
  'nor subscription_active — the reason 20260915000000 exists at all'
);

reset role;
select * from finish();
rollback;
