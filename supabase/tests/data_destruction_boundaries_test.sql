-- The edges of everything that deletes: who may write the audit trail, who may claim to be deleted,
-- which objects a purge is allowed to queue for R2, and what a deleted account leaves switched on.
--
-- Each section is a hole that was open, and each assertion was seen red before the migration that
-- closes it (20261114001100 .. 20261114001400; the audit-log grant is 20261114003000).

begin;
select plan(23);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('5c000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a1@boundary.test', 'x', now(), now()),
  ('5c000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a2@boundary.test', 'x', now(), now()),
  ('5c000000-0000-4000-8000-0000000000b1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b1@boundary.test', 'x', now(), now()),
  ('5c000000-0000-4000-8000-0000000000b2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b2@boundary.test', 'x', now(), now()),
  ('5c000000-0000-4000-8000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd1@boundary.test', 'x', now(), now()),
  ('5c000000-0000-4000-8000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'e1@boundary.test', 'x', now(), now()),
  ('5c000000-0000-4000-8000-0000000000e2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'e2@boundary.test', 'x', now(), now()),
  ('5c000000-0000-4000-8000-0000000000e3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'e3@boundary.test', 'x', now(), now())
on conflict do nothing;

-- CA is the attacker's couple, CV the victim's.
insert into public.couples (id, partner_a_id, partner_b_id, status) values
  ('5c000000-0000-4000-8000-00000000c0a0', '5c000000-0000-4000-8000-0000000000a1', '5c000000-0000-4000-8000-0000000000a2', 'active'),
  ('5c000000-0000-4000-8000-00000000c0b0', '5c000000-0000-4000-8000-0000000000b1', '5c000000-0000-4000-8000-0000000000b2', 'active');

-- ---------------------------------------------------------------------------
-- The audit log is written by the server, not by whoever asks
-- ---------------------------------------------------------------------------

select ok(
  not has_function_privilege('authenticated', 'public.admin_record_action(uuid, text, uuid, text, jsonb)', 'EXECUTE'),
  'a signed-in user cannot call admin_record_action, whose actor id is whatever the caller says'
);

-- The guard against the next one. 20261110000600 re-granted `authenticated` on every `admin_%`
-- function because "every one of them gates on an admin check internally", and the one that did
-- not was the audit writer. Anything a client can execute here must check for itself.
select is(
  array(
    select p.proname::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'admin\_%'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and p.prosrc !~ 'is_(support|billing|feedback)_admin\('
    order by 1
  ),
  array[]::text[],
  'every admin_ function a signed-in user can execute checks an admin role itself'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '5c000000-0000-4000-8000-0000000000a1', true);

select throws_ok(
  $$ select public.admin_record_action('5c000000-0000-4000-8000-0000000000b1', 'account.scrub',
       '5c000000-0000-4000-8000-0000000000a2', 'forged', null) $$,
  '42501',
  null,
  'and trying it directly is refused rather than writing a row attributed to somebody else'
);

-- ---------------------------------------------------------------------------
-- account_deleted_at is a fact the server records, not a field the client edits
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ update public.profiles set account_deleted_at = now() where id = '5c000000-0000-4000-8000-0000000000a1' $$,
  '42501',
  null,
  'a live account cannot mark itself deleted, which is what admin_purge_couple_archive gates on'
);

reset role;

select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'account_deleted_at', 'UPDATE'),
  'nor un-mark itself once scrubbed'
);

-- ---------------------------------------------------------------------------
-- A purge never takes a couple that is not an archive
-- ---------------------------------------------------------------------------
--
-- The cron reads its candidates without a lock, so a restore that commits between that read and
-- the delete would have its freshly reactivated couple deleted by id. Checking the status under
-- the row lock, inside the purge, is what makes the lost race harmless.

select public.purge_couple_data('5c000000-0000-4000-8000-00000000c0a0');

select ok(
  exists(select 1 from public.couples where id = '5c000000-0000-4000-8000-00000000c0a0'),
  'purge_couple_data leaves an active couple in place'
);

select is(
  (select count(*)::int from public.pending_object_deletions
   where key ilike '%5c000000-0000-4000-8000-00000000c0a0%'),
  0,
  'and queues none of its objects for deletion'
);

-- ---------------------------------------------------------------------------
-- The key collectors only queue what is in the owner's own folder
-- ---------------------------------------------------------------------------
--
-- The path columns are client-written with no constraint, and a queued key is deleted from R2
-- without a second look. The app writes ids in Swift's uppercase form, which is why the legitimate
-- fixtures below are uppercase and why the ownership test has to ignore case.

update public.profiles
set avatar_path = '5C000000-0000-4000-8000-0000000000B1/avatar.jpg',          -- the victim's own avatar
    partner_avatar_path = '5c000000-0000-4000-8000-0000000000a1/../5c000000-0000-4000-8000-0000000000b1/partner-avatar.jpg'
where id = '5c000000-0000-4000-8000-0000000000a1';

update public.profiles
set avatar_path = '5C000000-0000-4000-8000-0000000000A2/avatar.jpg'
where id = '5c000000-0000-4000-8000-0000000000a2';

select ok(
  has_column_privilege('authenticated', 'public.profiles', 'avatar_path', 'UPDATE'),
  'precondition: avatar_path is client-writable, which is what makes the next assertion matter'
);

select is(
  (select count(*)::int from private.profile_object_keys('5c000000-0000-4000-8000-0000000000a1') k
   where k ilike '%5c000000-0000-4000-8000-0000000000b1%'),
  0,
  'deleting an account cannot queue another person''s avatar, however its own row names it'
);

select ok(
  'avatars/5C000000-0000-4000-8000-0000000000A2/avatar.jpg'
    in (select private.profile_object_keys('5c000000-0000-4000-8000-0000000000a2')),
  'while the owner''s own avatar, in the case the app wrote it, is still queued'
);

insert into public.memories (id, couple_id, title) values
  ('5c000000-0000-4000-8000-00000000aaa1', '5c000000-0000-4000-8000-00000000c0a0', 'Ours'),
  ('5c000000-0000-4000-8000-00000000bbb1', '5c000000-0000-4000-8000-00000000c0b0', 'Theirs');
insert into public.memory_photos (memory_id, photo_path, position) values
  ('5c000000-0000-4000-8000-00000000aaa1', '5C000000-0000-4000-8000-00000000C0A0/5C000000-0000-4000-8000-00000000AAA1/MINE.jpg', 0),
  -- Copied from the victim couple's row: a member can insert any path into their own memory.
  ('5c000000-0000-4000-8000-00000000aaa1', '5C000000-0000-4000-8000-00000000C0B0/5C000000-0000-4000-8000-00000000BBB1/THEIRS.jpg', 1),
  ('5c000000-0000-4000-8000-00000000aaa1', '5c000000-0000-4000-8000-00000000c0a0/../5c000000-0000-4000-8000-00000000c0b0/x.jpg', 2),
  ('5c000000-0000-4000-8000-00000000bbb1', '5C000000-0000-4000-8000-00000000C0B0/5C000000-0000-4000-8000-00000000BBB1/THEIRS.jpg', 0);

insert into public.flights (id, couple_id) values
  ('5c000000-0000-4000-8000-00000000f0a0', '5c000000-0000-4000-8000-00000000c0a0');
insert into public.flight_documents (flight_id, uploaded_by, file_path) values
  ('5c000000-0000-4000-8000-00000000f0a0', '5c000000-0000-4000-8000-0000000000a1',
   '5c000000-0000-4000-8000-00000000c0b0/5c000000-0000-4000-8000-00000000f0b0/theirs.pdf');

select is(
  (select count(*)::int from private.couple_object_keys('5c000000-0000-4000-8000-00000000c0a0') k
   where k ilike '%5c000000-0000-4000-8000-00000000c0b0%'),
  0,
  'purging one couple cannot queue another couple''s photos or documents, by copied path or by ..'
);

select ok(
  'memory-photos/5C000000-0000-4000-8000-00000000C0A0/5C000000-0000-4000-8000-00000000AAA1/MINE.jpg'
    in (select private.couple_object_keys('5c000000-0000-4000-8000-00000000c0a0')),
  'while the couple''s own photo is still queued'
);

-- ---------------------------------------------------------------------------
-- Drawing pads are queued under the key the app actually wrote
-- ---------------------------------------------------------------------------
--
-- No column records a pad's path; the collectors rebuild it from ids, and built it in Postgres's
-- lowercase. The app writes `"\(coupleID)/\(personID)/pad.png"` from Swift UUIDs, which are
-- uppercase, R2 keys are case-sensitive, and the worker reads R2's 404 as "already gone".

select ok(
  'drawing-pads/5C000000-0000-4000-8000-00000000C0A0/5C000000-0000-4000-8000-0000000000A1/pad.png'
    in (select private.couple_object_keys('5c000000-0000-4000-8000-00000000c0a0')),
  'a couple purge queues each pad in the uppercase form the app uploads'
);

select ok(
  'drawing-pads/5C000000-0000-4000-8000-00000000C0A0/5C000000-0000-4000-8000-0000000000A1/pad.png'
    in (select private.profile_object_keys('5c000000-0000-4000-8000-0000000000a1')),
  'and so does an account deletion'
);

select ok(
  'drawing-pads/5c000000-0000-4000-8000-00000000c0a0/5c000000-0000-4000-8000-0000000000a1/pad.png'
    in (select private.profile_object_keys('5c000000-0000-4000-8000-0000000000a1')),
  'without dropping the lowercase form any other client may have used'
);

-- ---------------------------------------------------------------------------
-- A dormant closure is an account deletion
-- ---------------------------------------------------------------------------

update public.profiles
set avatar_path = '5C000000-0000-4000-8000-0000000000D1/avatar.jpg'
where id = '5c000000-0000-4000-8000-0000000000d1';

insert into public.game_sessions (id, couple_id, game_type, initiator_id) values
  ('5c000000-0000-4000-8000-00000000d5d5', null, 'trivia_battle', '5c000000-0000-4000-8000-0000000000d1');

select public.close_dormant_account('5c000000-0000-4000-8000-0000000000d1');

select ok(
  exists(select 1 from public.pending_object_deletions
         where key = 'avatars/5C000000-0000-4000-8000-0000000000D1/avatar.jpg'),
  'closing a dormant account queues its avatar for R2, before nulling the only column naming it'
);

select is(
  (select count(*)::int from public.game_sessions where id = '5c000000-0000-4000-8000-00000000d5d5'),
  0,
  'and deletes its solo sessions, as a self-serve deletion does'
);

select is(
  (select first_name from public.profiles where id = '5c000000-0000-4000-8000-0000000000d1'),
  'Deleted User',
  'and still scrubs the profile'
);

select lives_ok(
  $$ select public.close_dormant_account('5c000000-0000-4000-8000-0000000000d1') $$,
  'and is still safe to repeat'
);

-- ---------------------------------------------------------------------------
-- A deleted account cannot be paired with afterwards
-- ---------------------------------------------------------------------------

insert into public.invite_codes (code, inviter_id) values
  ('5C5C-E1E1', '5c000000-0000-4000-8000-0000000000e1'),
  ('5C5C-E3E3', '5c000000-0000-4000-8000-0000000000e3');

-- E1 asked E3 to pair, and E3 has not answered yet.
set local role authenticated;
select set_config('request.jwt.claim.sub', '5c000000-0000-4000-8000-0000000000e1', true);
select * from public.redeem_invite_code('5C5C-E3E3', 'code');
select public.delete_own_account();
reset role;

select is(
  (select status::text from public.invite_codes where code = '5C5C-E1E1'),
  'expired',
  'deleting an account expires the invite codes it had out'
);

select is(
  (select status from public.connection_requests
   where requester_id = '5c000000-0000-4000-8000-0000000000e1'),
  'declined',
  'and declines the requests it was waiting on, so nobody can accept one from a deleted account'
);

-- A stranger holding E1's old link taps it. Before, this auto-accepted into an active couple with
-- an account nobody can sign in to.
set local role authenticated;
select set_config('request.jwt.claim.sub', '5c000000-0000-4000-8000-0000000000e2', true);

select is(
  (select error_message from public.redeem_invite_code('5C5C-E1E1', 'link')),
  'Invite code is no longer valid',
  'a deleted account''s invite link no longer works'
);

reset role;

select is(
  (select count(*)::int from public.couples
   where status = 'active'
     and '5c000000-0000-4000-8000-0000000000e1' in (partner_a_id, partner_b_id)),
  0,
  'so no active couple is ever formed with it'
);

select * from finish();
rollback;
