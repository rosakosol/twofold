-- How a connection request records the way its code arrived.
--
-- The origin only ever changes wording on the inviter's accept screen, so the assertions about it
-- are modest. The ones that matter more are the two either side: that an older client which cannot
-- send an origin still redeems, and that adding this did not disturb the rate limiter — which is
-- the thing in this function that has been silently broken before, and which a rewrite of the
-- surrounding code is exactly how it broke.

begin;
select plan(16);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-7777-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'inviter@origin.test', 'x', now(), now()),
  ('aaaaaaaa-7777-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'linktapper@origin.test', 'x', now(), now()),
  ('aaaaaaaa-7777-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'typer@origin.test', 'x', now(), now()),
  ('aaaaaaaa-7777-0000-0000-00000000000d', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'guesser@origin.test', 'x', now(), now())
on conflict do nothing;

-- Two inviters, one code each. They were one inviter with two codes until auto-accept landed:
-- a tapped link now pairs immediately, so the first redemption leaves that inviter connected and
-- their second code unusable. Separate inviters keep the two paths independent.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values ('aaaaaaaa-7777-0000-0000-00000000000f', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'inviter2@origin.test', 'x', now(), now())
on conflict do nothing;

insert into public.invite_codes (code, inviter_id)
values ('AAAA-BBBB', 'aaaaaaaa-7777-0000-0000-00000000000a'),
       ('CCCC-DDDD', 'aaaaaaaa-7777-0000-0000-00000000000f');

-- ---------------------------------------------------------------------------
-- A tapped link
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-00000000000b","role":"authenticated"}';

select is(
  (select error_message from public.redeem_invite_code('AAAA-BBBB', 'link')),
  null, 'redeeming from a link succeeds'
);

reset role;

select is(
  (select origin::text from public.connection_requests where invite_code = 'AAAA-BBBB'),
  'link', 'and the request remembers it came from a link'
);

-- A tapped link connects them there and then.
select is(
  (select status from public.connection_requests where invite_code = 'AAAA-BBBB'),
  'accepted', 'a link pairs immediately rather than waiting to be accepted'
);
select is(
  (select count(*)::integer from public.couples
   where status = 'active'
     and ((partner_a_id = 'aaaaaaaa-7777-0000-0000-00000000000a' and partner_b_id = 'aaaaaaaa-7777-0000-0000-00000000000b')
       or (partner_b_id = 'aaaaaaaa-7777-0000-0000-00000000000a' and partner_a_id = 'aaaaaaaa-7777-0000-0000-00000000000b'))),
  1, 'and there is a real couple to show for it'
);

-- ---------------------------------------------------------------------------
-- A typed code, and an older client that sends no origin at all
-- ---------------------------------------------------------------------------
--
-- The single-argument call is what every installed build makes. It has to keep working, and it has
-- to land on the cautious side — a request that reads as needing more scrutiny, not less.

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-00000000000c","role":"authenticated"}';

select is(
  (select error_message from public.redeem_invite_code('CCCC-DDDD')),
  null, 'an older client redeeming with no origin still works'
);

reset role;

select is(
  (select origin::text from public.connection_requests where invite_code = 'CCCC-DDDD'),
  'code', 'and defaults to the more cautious reading'
);

-- The half that is not being given away: a typed code still waits for a person.
select is(
  (select status from public.connection_requests where invite_code = 'CCCC-DDDD'),
  'pending', 'a typed code still needs the inviter to accept'
);

-- ---------------------------------------------------------------------------
-- The inviter sees it
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-00000000000f","role":"authenticated"}';

select is(
  (select count(*)::integer from public.fetch_pending_connection_requests()),
  1, 'only the typed one is waiting on its inviter'
);

select is(
  (select origin::text from public.fetch_pending_connection_requests()),
  'code', 'and the accept screen can tell which kind it is'
);

reset role;

-- ---------------------------------------------------------------------------
-- The rate limiter still works
-- ---------------------------------------------------------------------------
--
-- This function has had a limiter that never fired: every rejection used to `raise exception`,
-- which aborted the transaction the attempt log was written in, so only *successful* redemptions
-- were ever counted — the one case that needs no limiting, and codes were brute-forceable at
-- unlimited rate (20260911000000). Rewriting the body is precisely how that comes back, so it is
-- pinned here rather than left to the migration that fixed it.

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-00000000000d","role":"authenticated"}';

select is(
  (select error_message from public.redeem_invite_code('ZZZZ-ZZZZ', 'code')),
  'Invite code not found', 'a bad guess is answered, not raised'
);

reset role;

select is(
  (select count(*)::integer from public.invite_redemption_attempts
   where redeemer_id = 'aaaaaaaa-7777-0000-0000-00000000000d'),
  1, 'and it is counted — an exception here would roll this row away'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-00000000000d","role":"authenticated"}';

-- Nine more failures takes this redeemer to the cap.
select is(
  (select count(*)::integer from (
    select public.redeem_invite_code('ZZZZ-ZZZZ', 'code') from generate_series(1, 9)
  ) t),
  9, 'nine further guesses are all answered'
);

select is(
  (select error_message from public.redeem_invite_code('AAAA-BBBB', 'link')),
  'Too many attempts — please wait a while before trying again.',
  'the eleventh is refused, whatever origin it claims'
);

reset role;

-- A refused attempt is not itself logged, so a blocked person cannot extend their own lockout by
-- retrying — the window drains on schedule.
select is(
  (select count(*)::integer from public.invite_redemption_attempts
   where redeemer_id = 'aaaaaaaa-7777-0000-0000-00000000000d'),
  10, 'and being refused does not extend the lockout'
);

-- ---------------------------------------------------------------------------
-- Auto-accept steps aside where there is something to decide
-- ---------------------------------------------------------------------------
--
-- Re-pairing inside 90 days offers the inviter their old memories back, and that choice exists
-- only at the moment of accepting — restoring reuses the couple row, so once a new one is created
-- there is nothing left to reuse. Pairing them silently would take the decision away for good.

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-7777-0000-0000-000000000011', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ex1@origin.test', 'x', now(), now()),
  ('aaaaaaaa-7777-0000-0000-000000000012', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ex2@origin.test', 'x', now(), now())
on conflict do nothing;

insert into public.couples (id, partner_a_id, partner_b_id, status, dissolved_at)
values ('cccccccc-7777-0000-0000-00000000000c',
        'aaaaaaaa-7777-0000-0000-000000000011',
        'aaaaaaaa-7777-0000-0000-000000000012',
        'dissolved', now() - interval '5 days');

insert into public.invite_codes (code, inviter_id)
values ('EEEE-FFFF', 'aaaaaaaa-7777-0000-0000-000000000011');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-000000000012","role":"authenticated"}';

select is(
  (select auto_accepted from public.redeem_invite_code('EEEE-FFFF', 'link')),
  false, 'a link does not auto-pair two people with an archive between them'
);

reset role;

select is(
  (select status from public.connection_requests where invite_code = 'EEEE-FFFF'),
  'pending', 'it stays a request, so the inviter is still asked about their memories'
);

select * from finish();
rollback;
