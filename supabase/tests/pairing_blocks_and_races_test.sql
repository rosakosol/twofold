-- Pairing against blocks and concurrent pairings. See 20261114000100's header.
--
--   1. A block declines the requests already open between the two, whichever of them blocked and
--      whichever way the request runs — so the blocked inviter cannot accept their way into a
--      couple, and a blocked requester cannot keep nudging.
--   2. Even a request that is somehow still pending cannot pair a blocked pair, or restore their
--      archive: the single-active-couple trigger refuses it.
--   3. The trigger takes a lock on each member when a couple becomes active, which is what stops
--      two simultaneous pairings both committing. A lock cannot be raced inside one transaction,
--      so this asserts the lock is held; the second-session behaviour is the database's.
--   4. A blocked ex cannot read the blocker's profile row; an ex who is not blocked still can.
--   5. The inviter lookup gives a blocked caller what a wrong code gets.

begin;
select plan(18);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
select ('cccccccc-1400-0000-0000-0000000000' || s)::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'p' || s || '@pairblock.test', 'x', now(), now()
from unnest(array['01','02','03','04','05','06','07','08','09','10','11','12','13']) as s
on conflict do nothing;

-- 01 inviter Ivy, 02 requester Rex, 03 bystander Xan
-- 04/05 Jo invites Kit, 06/07 Lou invites Max, 08/09 an active couple, 10/11 another
-- 12/13 an ex pair with no block

insert into public.invite_codes (code, inviter_id, status, expires_at) values
  ('PBLKAAAA', 'cccccccc-1400-0000-0000-000000000001', 'pending', now() + interval '3 days'),
  ('PBLKJJJJ', 'cccccccc-1400-0000-0000-000000000004', 'pending', now() + interval '3 days'),
  ('PBLKLLLL', 'cccccccc-1400-0000-0000-000000000006', 'pending', now() + interval '3 days'),
  ('PBLKIIII', 'cccccccc-1400-0000-0000-000000000001', 'pending', now() + interval '3 days');

-- ---------------------------------------------------------------------------
-- 1. The requester blocks the inviter while the request is open
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-1400-0000-0000-000000000002","role":"authenticated"}';
do $$ begin perform public.redeem_invite_code('PBLKAAAA', 'code'); end $$;
do $$ begin perform public.block_profile('cccccccc-1400-0000-0000-000000000001'); end $$;
reset role;

select is(
  (select status from public.connection_requests
   where inviter_id = 'cccccccc-1400-0000-0000-000000000001'
     and requester_id = 'cccccccc-1400-0000-0000-000000000002'),
  'declined',
  'blocking the inviter declines the request you sent them'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-1400-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$ select public.respond_to_connection_request(
       (select id from public.connection_requests
        where requester_id = 'cccccccc-1400-0000-0000-000000000002'), true) $$,
  'This request has already been responded to',
  'so the blocked inviter cannot accept it'
);
reset role;

-- ---------------------------------------------------------------------------
-- 2. The backstop: a request still pending between a blocked pair
-- ---------------------------------------------------------------------------

-- As if it predated the trigger.
update public.connection_requests set status = 'pending', responded_at = null
where requester_id = 'cccccccc-1400-0000-0000-000000000002';

set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-1400-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$ select public.respond_to_connection_request(
       (select id from public.connection_requests
        where requester_id = 'cccccccc-1400-0000-0000-000000000002'), true) $$,
  '42501', 'This connection is no longer available',
  'accepting a pending request across a block is refused at the couple itself'
);
reset role;

select is(
  (select count(*)::int from public.couples
   where status = 'active'
     and 'cccccccc-1400-0000-0000-000000000002' in (partner_a_id, partner_b_id)),
  0,
  'and no couple was created'
);

-- Their old couple, dissolved and still inside its 90 days.
insert into public.couples (id, partner_a_id, partner_b_id, status, dissolved_at, dissolved_by)
values ('dddddddd-1400-0000-0000-0000000000a1',
        'cccccccc-1400-0000-0000-000000000001', 'cccccccc-1400-0000-0000-000000000002',
        'dissolved', now() - interval '2 days', 'cccccccc-1400-0000-0000-000000000002');

-- Independent of the case above: whatever it did, the request is pending again and nobody is
-- paired, so a refusal here can only be the block's.
delete from public.couples
where status = 'active' and 'cccccccc-1400-0000-0000-000000000002' in (partner_a_id, partner_b_id);
update public.connection_requests set status = 'pending', responded_at = null
where requester_id = 'cccccccc-1400-0000-0000-000000000002';

set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-1400-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$ select public.respond_to_connection_request(
       (select id from public.connection_requests
        where requester_id = 'cccccccc-1400-0000-0000-000000000002'), true, true) $$,
  '42501', 'This connection is no longer available',
  'restoring the archive across a block is refused too'
);
reset role;

select is(
  (select status::text from public.couples where id = 'dddddddd-1400-0000-0000-0000000000a1'),
  'dissolved',
  'and the archive stays an archive'
);

-- ---------------------------------------------------------------------------
-- 1, other way round: the inviter blocks the requester
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-1400-0000-0000-000000000005","role":"authenticated"}';
do $$ begin perform public.redeem_invite_code('PBLKJJJJ', 'code'); end $$;
set local request.jwt.claims = '{"sub":"cccccccc-1400-0000-0000-000000000004","role":"authenticated"}';
do $$ begin perform public.block_profile('cccccccc-1400-0000-0000-000000000005'); end $$;
reset role;

select is(
  (select status from public.connection_requests
   where requester_id = 'cccccccc-1400-0000-0000-000000000005'),
  'declined',
  'blocking a requester declines their request'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-1400-0000-0000-000000000005","role":"authenticated"}';
select throws_ok(
  $$ select public.send_connection_request_reminder(
       (select id from public.connection_requests
        where requester_id = 'cccccccc-1400-0000-0000-000000000005')) $$,
  'This request is no longer pending',
  'so the blocked requester cannot nudge the person who blocked them'
);
reset role;

-- A block inserted straight into the table, which its RLS allows, gets the same treatment.
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-1400-0000-0000-000000000007","role":"authenticated"}';
do $$ begin perform public.redeem_invite_code('PBLKLLLL', 'code'); end $$;
set local request.jwt.claims = '{"sub":"cccccccc-1400-0000-0000-000000000006","role":"authenticated"}';
insert into public.blocked_profiles (blocker_id, blocked_id)
values ('cccccccc-1400-0000-0000-000000000006', 'cccccccc-1400-0000-0000-000000000007');
reset role;

select is(
  (select status from public.connection_requests
   where requester_id = 'cccccccc-1400-0000-0000-000000000007'),
  'declined',
  'a block written directly to the table declines the request as well'
);

-- ---------------------------------------------------------------------------
-- 3. The lock, and what does not take it
-- ---------------------------------------------------------------------------

insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('dddddddd-1400-0000-0000-0000000000b1',
        'cccccccc-1400-0000-0000-000000000008', 'cccccccc-1400-0000-0000-000000000009', 'active');

select ok(
  exists (
    select 1 from pg_locks
    where locktype = 'advisory' and pid = pg_backend_pid() and objsubid = 1 and granted
      and ((classid::bigint << 32) | objid::bigint)
          = hashtextextended('twofold.couple_member:cccccccc-1400-0000-0000-000000000008', 0)
  ),
  'activating a couple locks its first member until commit'
);

select ok(
  exists (
    select 1 from pg_locks
    where locktype = 'advisory' and pid = pg_backend_pid() and objsubid = 1 and granted
      and ((classid::bigint << 32) | objid::bigint)
          = hashtextextended('twofold.couple_member:cccccccc-1400-0000-0000-000000000009', 0)
  ),
  'and its second'
);

select throws_ok(
  $$ insert into public.couples (partner_a_id, partner_b_id, status)
     values ('cccccccc-1400-0000-0000-000000000003', 'cccccccc-1400-0000-0000-000000000009', 'active') $$,
  'One or both partners are already in an active couple',
  'a second active couple for the same person is still refused'
);

-- An active couple with a block written behind block_profile's back. Its ordinary updates must not
-- start failing: only the transition into active is a pairing.
insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('dddddddd-1400-0000-0000-0000000000c1',
        'cccccccc-1400-0000-0000-000000000010', 'cccccccc-1400-0000-0000-000000000011', 'active');
insert into public.blocked_profiles (blocker_id, blocked_id)
values ('cccccccc-1400-0000-0000-000000000010', 'cccccccc-1400-0000-0000-000000000011');

select lives_ok(
  $$ update public.couples set max_distance_km = 123
     where id = 'dddddddd-1400-0000-0000-0000000000c1' $$,
  'an update to a couple that is already active is not treated as a pairing'
);

-- ---------------------------------------------------------------------------
-- 4. Reading an ex's profile
-- ---------------------------------------------------------------------------

insert into public.couples (partner_a_id, partner_b_id, status, dissolved_at, dissolved_by)
values ('cccccccc-1400-0000-0000-000000000012', 'cccccccc-1400-0000-0000-000000000013',
        'dissolved', now() - interval '2 days', 'cccccccc-1400-0000-0000-000000000012');

-- Rex blocked Ivy, and they share the archive inserted above.
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-1400-0000-0000-000000000001","role":"authenticated"}';
select is(
  (select count(*)::int from public.profiles where id = 'cccccccc-1400-0000-0000-000000000002'),
  0,
  'a blocked ex cannot read the blocker''s profile'
);

set local request.jwt.claims = '{"sub":"cccccccc-1400-0000-0000-000000000002","role":"authenticated"}';
select is(
  (select count(*)::int from public.profiles where id = 'cccccccc-1400-0000-0000-000000000001'),
  1,
  'the blocker can still read theirs, which is what their archive shows'
);

set local request.jwt.claims = '{"sub":"cccccccc-1400-0000-0000-000000000012","role":"authenticated"}';
select is(
  (select count(*)::int from public.profiles where id = 'cccccccc-1400-0000-0000-000000000013'),
  1,
  'an ex with no block between them still reads the other''s profile, as before'
);

-- ---------------------------------------------------------------------------
-- 5. Looking up who sent a code
-- ---------------------------------------------------------------------------

-- Ivy's second code, held by Rex, who blocked her.
set local request.jwt.claims = '{"sub":"cccccccc-1400-0000-0000-000000000002","role":"authenticated"}';
select is(
  (select count(*)::int from public.get_invite_code_inviter_info('PBLKIIII')),
  0,
  'a blocked pair gets nothing back from the inviter lookup, the same as a wrong code'
);

set local request.jwt.claims = '{"sub":"cccccccc-1400-0000-0000-000000000003","role":"authenticated"}';
select is(
  (select count(*)::int from public.get_invite_code_inviter_info('PBLKIIII')),
  1,
  'anyone else holding the code still sees who sent it'
);
reset role;

select * from finish();
rollback;
