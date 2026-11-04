-- claim_flight_tracking_slot: how add-flight spends a slot, as one check-and-write under a lock.
--
-- The concurrency this exists for cannot be shown in one transaction; that half is
-- functions/_shared/flight-allowance-races.test.ts, against the local stack. This pins what the
-- function answers: within the allowance it tracks and records, past it it refuses and writes
-- nothing, a flight already paid for costs nothing, a zero override freezes, the count follows the
-- two people rather than the couple row, and only the service role can call it.

begin;
select plan(16);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-7777-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@claim.test', 'x', now(), now(), now()),
  ('bbbbbbbb-7777-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@claim.test', 'x', now(), now(), now());

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-7777-0000-0000-000000000003', 'aaaaaaaa-7777-0000-0000-000000000001', 'bbbbbbbb-7777-0000-0000-000000000002');

-- Saved untracked, as add-flight now inserts every flight before claiming its slot.
insert into public.flights (id, couple_id, status, tracking_enabled, cancelled, diverted, shared)
values
  ('f1111111-7777-0000-0000-000000000011', 'cccccccc-7777-0000-0000-000000000003', 'scheduled', false, false, false, true),
  ('f2222222-7777-0000-0000-000000000022', 'cccccccc-7777-0000-0000-000000000003', 'scheduled', false, false, false, true),
  ('f3333333-7777-0000-0000-000000000033', 'cccccccc-7777-0000-0000-000000000003', 'scheduled', false, false, false, true);

-- MARK: within, then past, the Plus allowance of two

select is(
  public.claim_flight_tracking_slot('f1111111-7777-0000-0000-000000000011', 'aaaaaaaa-7777-0000-0000-000000000001') - 'tier',
  jsonb_build_object('tracking', true, 'limit', 2, 'used', 1),
  'the first flight of the month is tracked'
);
select is(
  (select tracking_enabled from public.flights where id = 'f1111111-7777-0000-0000-000000000011'),
  true, 'and its row now says so'
);
select is(
  (select count(*)::integer from public.flight_additions where flight_id = 'f1111111-7777-0000-0000-000000000011'),
  1, 'with one ledger row, recorded against the person who added it'
);

select is(
  (public.claim_flight_tracking_slot('f2222222-7777-0000-0000-000000000022', 'bbbbbbbb-7777-0000-0000-000000000002') ->> 'tracking')::boolean,
  true, 'the second, by the other partner, draws on the same allowance'
);

select is(
  public.claim_flight_tracking_slot('f3333333-7777-0000-0000-000000000033', 'aaaaaaaa-7777-0000-0000-000000000001') - 'tier',
  jsonb_build_object('tracking', false, 'limit', 2, 'used', 2),
  'the third is refused'
);
select is(
  (select tracking_enabled from public.flights where id = 'f3333333-7777-0000-0000-000000000033'),
  false, 'and stays untracked'
);
select is(
  (select count(*)::integer from public.flight_additions where flight_id = 'f3333333-7777-0000-0000-000000000033'),
  0, 'with no ledger row written for a refusal'
);

-- A second claim for a flight already paid for spends nothing: one slot per flight, ever.
select is(
  public.claim_flight_tracking_slot('f1111111-7777-0000-0000-000000000011', 'aaaaaaaa-7777-0000-0000-000000000001') - 'tier',
  jsonb_build_object('tracking', true, 'limit', 2, 'used', 2),
  'a flight already paid for is tracked without spending again'
);
select is(public.flights_used_this_month('cccccccc-7777-0000-0000-000000000003'), 2, 'still two used');

-- MARK: overrides, which replace the tier's number in both directions

insert into private.flight_limit_overrides (profile_id, monthly_limit, note)
values ('aaaaaaaa-7777-0000-0000-000000000001', 3, 'test');
select is(
  (public.claim_flight_tracking_slot('f3333333-7777-0000-0000-000000000033', 'aaaaaaaa-7777-0000-0000-000000000001') ->> 'tracking')::boolean,
  true, 'an override above the tier lets the third through'
);

update public.flights set tracking_enabled = false where id = 'f3333333-7777-0000-0000-000000000033';
delete from public.flight_additions where flight_id = 'f3333333-7777-0000-0000-000000000033';
update private.flight_limit_overrides set monthly_limit = 0 where profile_id = 'aaaaaaaa-7777-0000-0000-000000000001';
select is(
  (public.claim_flight_tracking_slot('f3333333-7777-0000-0000-000000000033', 'aaaaaaaa-7777-0000-0000-000000000001') ->> 'tracking')::boolean,
  false, 'a zero override freezes tracking, rather than reading as unlimited'
);
delete from private.flight_limit_overrides where profile_id = 'aaaaaaaa-7777-0000-0000-000000000001';

-- MARK: the count follows the people, so a fresh couples row is not a fresh month

update public.couples set status = 'dissolved' where id = 'cccccccc-7777-0000-0000-000000000003';
insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-7777-0000-0000-000000000004', 'aaaaaaaa-7777-0000-0000-000000000001', 'bbbbbbbb-7777-0000-0000-000000000002');
insert into public.flights (id, couple_id, status, tracking_enabled, cancelled, diverted, shared)
values ('f4444444-7777-0000-0000-000000000044', 'cccccccc-7777-0000-0000-000000000004', 'scheduled', false, false, false, true);
select is(
  public.claim_flight_tracking_slot('f4444444-7777-0000-0000-000000000044', 'aaaaaaaa-7777-0000-0000-000000000001') - 'tier',
  jsonb_build_object('tracking', false, 'limit', 2, 'used', 2),
  're-pairing into a new couples row does not hand back the month'
);

-- MARK: who can call it

select throws_ok(
  $$ select public.claim_flight_tracking_slot('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-7777-0000-0000-000000000001') $$,
  'P0002', null, 'a flight that does not exist is an error, not a claim'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$ select public.claim_flight_tracking_slot('f4444444-7777-0000-0000-000000000044', 'aaaaaaaa-7777-0000-0000-000000000001') $$,
  '42501', null, 'a signed-in client cannot claim a slot itself'
);
reset role;
set local role anon;
select throws_ok(
  $$ select public.claim_flight_tracking_slot('f4444444-7777-0000-0000-000000000044', 'aaaaaaaa-7777-0000-0000-000000000001') $$,
  '42501', null, 'nor can anon'
);
reset role;
set local role service_role;
select lives_ok(
  $$ select public.claim_flight_tracking_slot('f4444444-7777-0000-0000-000000000044', 'aaaaaaaa-7777-0000-0000-000000000001') $$,
  'add-flight, as the service role, can'
);
reset role;

select * from finish();
rollback;
