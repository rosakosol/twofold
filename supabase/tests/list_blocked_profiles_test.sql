-- The list the Blocked people screen reads, and the unblock it exists to reach.
--
-- `unblock_profile` shipped with blocking and had no caller, because nothing could list who you
-- had blocked: the blocked person's profile row is not readable by the blocker. What is pinned:
--
--   1. You see your own blocks, by name, and nobody else's.
--   2. You never see who has blocked you — the one thing blocking must not reveal.
--   3. Unblocking from the list takes the person off it.
--   4. Signed-out callers get nothing at all.

begin;
select plan(8);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at, raw_user_meta_data)
values
  ('bbbbbbbb-7878-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ana@blocklist.test', 'x', now(), now(), '{"first_name":"Ana"}'),
  ('bbbbbbbb-7878-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bo@blocklist.test',  'x', now(), now(), '{"first_name":"Bo"}'),
  ('bbbbbbbb-7878-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cy@blocklist.test',  'x', now(), now(), '{"first_name":"Cy"}')
on conflict do nothing;

update public.profiles set first_name = 'Bo' where id = 'bbbbbbbb-7878-0000-0000-00000000000b';
update public.profiles set first_name = 'Cy' where id = 'bbbbbbbb-7878-0000-0000-00000000000c';

-- Ana blocks Bo. Cy blocks Ana.
insert into public.blocked_profiles (blocker_id, blocked_id) values
  ('bbbbbbbb-7878-0000-0000-00000000000a', 'bbbbbbbb-7878-0000-0000-00000000000b'),
  ('bbbbbbbb-7878-0000-0000-00000000000c', 'bbbbbbbb-7878-0000-0000-00000000000a');

select ok(
  not has_function_privilege('anon', 'public.list_blocked_profiles()', 'EXECUTE'),
  'signed out, there is no list to read'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-7878-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select count(*)::int from public.list_blocked_profiles()),
  1,
  'Ana sees exactly the one person she blocked'
);

select is(
  (select first_name from public.list_blocked_profiles()),
  'Bo',
  'by the name she knows them by, although she cannot read their profile row'
);

select is(
  (select count(*)::int from public.profiles where id = 'bbbbbbbb-7878-0000-0000-00000000000b'),
  0,
  'precondition: the blocked profile really is unreadable to her directly'
);

select ok(
  not exists (select 1 from public.list_blocked_profiles() where profile_id = 'bbbbbbbb-7878-0000-0000-00000000000c'),
  'Cy blocked Ana, and nothing on Ana''s list says so'
);

select lives_ok(
  $$ select public.unblock_profile('bbbbbbbb-7878-0000-0000-00000000000b') $$,
  'unblocking from the list succeeds'
);

select is(
  (select count(*)::int from public.list_blocked_profiles()),
  0,
  'and the person is off the list'
);

reset role;

select ok(
  exists (select 1 from public.blocked_profiles
          where blocker_id = 'bbbbbbbb-7878-0000-0000-00000000000c'
            and blocked_id = 'bbbbbbbb-7878-0000-0000-00000000000a'),
  'Ana unblocking Bo leaves Cy''s block of her exactly where it was'
);

select * from finish();
rollback;
