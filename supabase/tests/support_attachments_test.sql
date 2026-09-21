-- An upload endpoint hands out a capability: a presigned PUT is permission to write specific bytes
-- to a specific place, and it is redeemed by whoever holds it. So the questions are about what the
-- caller is allowed to influence.
--
-- The key above all. It is built server-side from the thread id and a fresh uuid, and the filename
-- only ever contributes a sanitised extension — because a caller-supplied key is a caller-supplied
-- path, and a presigned PUT for `../avatars/{someone}/avatar.jpg` is an endpoint for overwriting
-- other people's files.

begin;
select plan(11);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('99999999-4444-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','agent@att.test','x',now(),now(),now()),
  ('99999999-4444-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','nosy@att.test','x',now(),now(),now());
insert into public.profiles (id, first_name) values
  ('99999999-4444-0000-0000-000000000001','Agt'), ('99999999-4444-0000-0000-000000000002','Nos')
on conflict (id) do update set first_name = excluded.first_name;
insert into public.feedback_admins (profile_id, role) values ('99999999-4444-0000-0000-000000000001','support');
insert into public.support_threads (id, thread_key, email)
values ('99999999-4444-cccc-0000-000000000001','k|c@att.test','c@att.test');

set local role authenticated;

-- ---------------------------------------------------------------------------
-- Who may reserve one
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub','99999999-4444-0000-0000-000000000002',true);
select throws_ok(
  $$ select public.reserve_support_attachment('99999999-4444-cccc-0000-000000000001','a.png','image/png',100) $$,
  '42501', null, 'a signed-in non-admin cannot reserve an upload'
);

select set_config('request.jwt.claim.sub','99999999-4444-0000-0000-000000000001',true);

-- ---------------------------------------------------------------------------
-- The key is ours
-- ---------------------------------------------------------------------------

select matches(
  public.reserve_support_attachment('99999999-4444-cccc-0000-000000000001','holiday.PNG','image/png',2048) #>> '{key}',
  '^support/99999999-4444-cccc-0000-000000000001/[0-9a-f-]{36}\.png$',
  'the key is the thread, a fresh uuid, and a lowercased extension'
);

-- The case that matters. Nothing from the filename reaches the path.
select matches(
  public.reserve_support_attachment('99999999-4444-cccc-0000-000000000001','../../avatars/victim/avatar.jpg','image/jpeg',2048) #>> '{key}',
  '^support/99999999-4444-cccc-0000-000000000001/[0-9a-f-]{36}\.jpg$',
  'a filename full of traversal produces a key entirely under our own prefix'
);

select matches(
  public.reserve_support_attachment('99999999-4444-cccc-0000-000000000001','no-extension','text/plain',10) #>> '{key}',
  '\.bin$',
  'and a name with no extension gets a safe default rather than a bare path'
);

-- The displayed name is kept as the sender typed it — it is theirs, and only the key is ours.
-- Read as the owner: `authenticated` cannot see this table at all, which is the point of it having
-- no policies, and a test reaching in directly would be asserting a permission the console lacks.
reset role;
select is(
  (select filename from public.support_attachments where content_type='image/jpeg'),
  '../../avatars/victim/avatar.jpg',
  'while the name shown in the mail is preserved exactly'
);
set local role authenticated;
select set_config('request.jwt.claim.sub','99999999-4444-0000-0000-000000000001',true);

-- ---------------------------------------------------------------------------
-- Limits are enforced where the capability is granted
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ select public.reserve_support_attachment('99999999-4444-cccc-0000-000000000001','huge.zip','application/zip', 11534336) $$,
  '22023', null, 'over 10MB is refused, because the send has to hold it in memory'
);

select throws_ok(
  $$ select public.reserve_support_attachment('99999999-4444-cccc-0000-000000000001','empty.txt','text/plain', 0) $$,
  '22023', null, 'and so is nothing at all'
);

select throws_ok(
  $$ select public.reserve_support_attachment('00000000-0000-0000-0000-0000000000ff','a.png','image/png',10) $$,
  'P0001', 'no such thread', 'a conversation that does not exist is refused by name'
);

-- Three exist already; two more reach the ceiling of five pending.
select public.reserve_support_attachment('99999999-4444-cccc-0000-000000000001','d.png','image/png',10);
select public.reserve_support_attachment('99999999-4444-cccc-0000-000000000001','e.png','image/png',10);
select throws_ok(
  $$ select public.reserve_support_attachment('99999999-4444-cccc-0000-000000000001','f.png','image/png',10) $$,
  '22023', null, 'and a sixth pending upload is refused'
);

-- ---------------------------------------------------------------------------
-- Binding, and the sweep
-- ---------------------------------------------------------------------------

reset role;
select is(
  (select count(*)::integer from private.purge_dangling_support_attachments('1 day')),
  0, 'nothing recent is swept, so an in-progress compose is never interrupted'
);

-- Aged past the window, with nothing pointing at them: abandoned.
update public.support_attachments set created_at = now() - interval '2 days'
where thread_id = '99999999-4444-cccc-0000-000000000001';

select is(
  (select count(*)::integer from private.purge_dangling_support_attachments('1 day')),
  5, 'but files whose reply was never sent are collected, keys returned for the bucket'
);

reset role;
select * from finish();
rollback;
