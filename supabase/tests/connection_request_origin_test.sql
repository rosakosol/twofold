-- How a connection request records the way its code arrived.
--
-- The origin only ever changes wording on the inviter's accept screen, so the assertions about it
-- are modest. The ones that matter more are the two either side: that an older client which cannot
-- send an origin still redeems, and that adding this did not disturb the rate limiter — which is
-- the thing in this function that has been silently broken before, and which a rewrite of the
-- surrounding code is exactly how it broke.

begin;
select plan(11);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-7777-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'inviter@origin.test', 'x', now(), now()),
  ('aaaaaaaa-7777-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'linktapper@origin.test', 'x', now(), now()),
  ('aaaaaaaa-7777-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'typer@origin.test', 'x', now(), now()),
  ('aaaaaaaa-7777-0000-0000-00000000000d', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'guesser@origin.test', 'x', now(), now())
on conflict do nothing;

insert into public.invite_codes (code, inviter_id)
values ('AAAA-BBBB', 'aaaaaaaa-7777-0000-0000-00000000000a'),
       ('CCCC-DDDD', 'aaaaaaaa-7777-0000-0000-00000000000a');

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

-- ---------------------------------------------------------------------------
-- The inviter sees it
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select count(*)::integer from public.fetch_pending_connection_requests()),
  2, 'both requests are waiting on the inviter'
);

select is(
  (select origin::text from public.fetch_pending_connection_requests() where requester_id = 'aaaaaaaa-7777-0000-0000-00000000000b'),
  'link', 'and the accept screen can tell which is which'
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

select * from finish();
rollback;
