-- Blocking someone: what it stops, what it must not touch, and what it must not reveal.
--
-- Three things are worth pinning here, and the wording of the refusal is one of them.
--
--   1. A block stops an invite code working, in both directions. Blocking someone who then hands
--      you a code must fail just as surely as them trying to redeem yours.
--   2. The refusal is indistinguishable from a wrong code. A blocked person who is told they have
--      been blocked has learned the person they were looking for is reachable and paying
--      attention — the opposite of what a block is for.
--   3. Blocking a partner disconnects them but does NOT touch the shared archive. Deleting shared
--      data is the 90-day timer's job and nothing else's (20261005000000). A block that also
--      destroyed the archive would be exactly the unilateral destruction that migration removed,
--      wearing a safety label.

begin;
select plan(10);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('bbbbbbbb-7777-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ana@block.test', 'x', now(), now()),
  ('bbbbbbbb-7777-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bo@block.test',  'x', now(), now())
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Blocking a current partner
-- ---------------------------------------------------------------------------

insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('dddddddd-7777-0000-0000-00000000000c',
        'bbbbbbbb-7777-0000-0000-00000000000a',
        'bbbbbbbb-7777-0000-0000-00000000000b',
        'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-7777-0000-0000-00000000000a","role":"authenticated"}';

select lives_ok(
  $$ select public.block_profile('bbbbbbbb-7777-0000-0000-00000000000b') $$,
  'blocking a current partner succeeds'
);

reset role;

select is(
  (select status from public.couples where id = 'dddddddd-7777-0000-0000-00000000000c'),
  'dissolved',
  'blocking a current partner disconnects them'
);

select isnt(
  (select scheduled_purge_at from public.couples where id = 'dddddddd-7777-0000-0000-00000000000c'),
  null,
  'the archive gets its normal 90-day clock, same as any other disconnection'
);

select ok(
  (select scheduled_purge_at from public.couples where id = 'dddddddd-7777-0000-0000-00000000000c')
    > now() + interval '89 days',
  'blocking does not bring the deletion date forward — that is the timer''s job alone'
);

select ok(
  exists (select 1 from public.couples where id = 'dddddddd-7777-0000-0000-00000000000c'),
  'the archive itself still exists after a block'
);

-- ---------------------------------------------------------------------------
-- What a block does to an invite code
-- ---------------------------------------------------------------------------

-- Bo invites; Ana (who blocked Bo) tries to redeem.
insert into public.invite_codes (code, inviter_id, status, expires_at)
values ('BLOCK1', 'bbbbbbbb-7777-0000-0000-00000000000b', 'pending', now() + interval '3 days');

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-7777-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select error_message from public.redeem_invite_code('BLOCK1')),
  'Invite code not found',
  'the blocker cannot redeem the blocked person''s code either — a block works both ways'
);

reset role;

-- Ana invites; Bo (who Ana blocked) tries to redeem. Bo has blocked nobody.
insert into public.invite_codes (code, inviter_id, status, expires_at)
values ('BLOCK2', 'bbbbbbbb-7777-0000-0000-00000000000a', 'pending', now() + interval '3 days');

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-7777-0000-0000-00000000000b","role":"authenticated"}';

select is(
  (select error_message from public.redeem_invite_code('BLOCK2')),
  'Invite code not found',
  'a blocked person redeeming the blocker''s code is refused'
);

select is(
  (select error_message from public.redeem_invite_code('NOSUCH')),
  'Invite code not found',
  'and gets exactly the same message a genuinely missing code gets'
);

-- ---------------------------------------------------------------------------
-- Being blocked is not something you can find out
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from public.blocked_profiles),
  0,
  'the blocked person cannot see the row that blocks them'
);

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-7777-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select count(*)::int from public.blocked_profiles),
  1,
  'the blocker can see their own'
);

reset role;
select * from finish();
rollback;
