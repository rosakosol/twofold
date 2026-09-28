-- What a subscription actually buys, now that it is the database deciding rather than a paywall
-- screen.
--
-- Two ways to be wrong here and both are expensive. Too strict and somebody who is paying cannot
-- use what they bought; too loose and the product is free. So this asserts both directions on the
-- same pair of couples, and also the things that must stay open however this goes:
--
--   * Reading is never gated. A lapsed couple sees their whole history — that is the difference
--     between a subscription and a hostage.
--   * Deleting is never gated. Removing your own memory is not a feature anyone buys, and putting
--     it behind a paywall would price the privacy policy's erasure promise.
--   * Either partner's subscription covers both, which is what the terms promise.

begin;
select plan(16);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('eeeeeeee-9999-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'paid-a@gate.test', 'x', now(), now()),
  ('eeeeeeee-9999-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'paid-b@gate.test', 'x', now(), now()),
  ('eeeeeeee-9999-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'free-a@gate.test', 'x', now(), now()),
  ('eeeeeeee-9999-0000-0000-00000000000d', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'free-b@gate.test', 'x', now(), now())
on conflict do nothing;

-- Only partner B pays, to prove coverage is an OR across the couple rather than per person.
update public.profiles set subscription_active = true
where id = 'eeeeeeee-9999-0000-0000-00000000000b';
update public.profiles set subscription_active = false
where id in ('eeeeeeee-9999-0000-0000-00000000000a',
             'eeeeeeee-9999-0000-0000-00000000000c',
             'eeeeeeee-9999-0000-0000-00000000000d');

insert into public.couples (id, partner_a_id, partner_b_id, status)
values
  ('ffffffff-9999-0000-0000-0000000000a1', 'eeeeeeee-9999-0000-0000-00000000000a', 'eeeeeeee-9999-0000-0000-00000000000b', 'active'),
  ('ffffffff-9999-0000-0000-0000000000b1', 'eeeeeeee-9999-0000-0000-00000000000c', 'eeeeeeee-9999-0000-0000-00000000000d', 'active');

-- A memory each, inserted before the gate applies, so the lapsed couple has something to read.
insert into public.memories (id, couple_id, title, occurred_at)
values
  ('11111111-9999-0000-0000-0000000000a1', 'ffffffff-9999-0000-0000-0000000000a1', 'Paid memory', now()),
  ('11111111-9999-0000-0000-0000000000b1', 'ffffffff-9999-0000-0000-0000000000b1', 'Free memory', now());

select is(public.couple_is_subscribed('ffffffff-9999-0000-0000-0000000000a1'), true,
  'a couple where one partner pays is covered');
select is(public.couple_is_subscribed('ffffffff-9999-0000-0000-0000000000b1'), false,
  'a couple where neither pays is not');

-- ---------------------------------------------------------------------------
-- The paying couple can still do everything
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"eeeeeeee-9999-0000-0000-00000000000a","role":"authenticated"}';

select lives_ok(
  $$ insert into public.memories (couple_id, title, occurred_at)
     values ('ffffffff-9999-0000-0000-0000000000a1', 'Another', now()) $$,
  'the non-paying partner of a paying couple can still add — coverage is the couple''s'
);

select lives_ok(
  $$ update public.memories set title = 'Edited' where id = '11111111-9999-0000-0000-0000000000a1' $$,
  'and can still edit'
);

-- ---------------------------------------------------------------------------
-- The lapsed couple is read-only
-- ---------------------------------------------------------------------------

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"eeeeeeee-9999-0000-0000-00000000000c","role":"authenticated"}';

select throws_ok(
  $$ insert into public.memories (couple_id, title, occurred_at)
     values ('ffffffff-9999-0000-0000-0000000000b1', 'Nope', now()) $$,
  '42501', NULL,
  'a lapsed couple cannot add a memory'
);

select throws_ok(
  $$ insert into public.trips (couple_id, origin_id, destination_id, departure_at, arrival_at, category)
     values ('ffffffff-9999-0000-0000-0000000000b1',
             (select id from public.places limit 1), (select id from public.places limit 1),
             now(), now() + interval '1 day', 'together') $$,
  '42501', NULL,
  'nor a trip'
);

-- An UPDATE blocked by RLS is not an error: the row simply is not visible to write, so nothing
-- changes. Asserted on the title rather than on a thrown code for that reason.
update public.memories set title = 'Sneaky' where id = '11111111-9999-0000-0000-0000000000b1';
select is(
  (select title from public.memories where id = '11111111-9999-0000-0000-0000000000b1'),
  'Free memory',
  'nor edit one they already have'
);

-- ...but reading and deleting stay open.

select is(
  (select title from public.memories where id = '11111111-9999-0000-0000-0000000000b1'),
  'Free memory',
  'a lapsed couple can still read their history'
);

select lives_ok(
  $$ delete from public.memories where id = '11111111-9999-0000-0000-0000000000b1' $$,
  'and can still delete it — erasure is not a paid feature'
);

-- ---------------------------------------------------------------------------
-- Inviting
-- ---------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.invite_codes (code, inviter_id, status, expires_at)
     values ('FREEFREE', 'eeeeeeee-9999-0000-0000-00000000000c', 'pending', now() + interval '3 days') $$,
  '42501', NULL,
  'an unsubscribed person cannot create an invite code'
);

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"eeeeeeee-9999-0000-0000-00000000000b","role":"authenticated"}';

select lives_ok(
  $$ insert into public.invite_codes (code, inviter_id, status, expires_at)
     values ('PAIDPAID', 'eeeeeeee-9999-0000-0000-00000000000b', 'pending', now() + interval '3 days') $$,
  'a subscriber can'
);

select is(
  (select count(*)::int from public.memories where couple_id = 'ffffffff-9999-0000-0000-0000000000a1'),
  2,
  'the paying couple''s additions all landed'
);

-- ---------------------------------------------------------------------------
-- Flights, which are the expensive ones
-- ---------------------------------------------------------------------------
--
-- Every other kind of content is gated by an RLS policy. Flights cannot be: nothing grants clients
-- INSERT on `public.flights` at all, because `add-flight` writes them as service_role after paying
-- AeroAPI for the lookup, and `enable_flight_tracking` is the one that starts the polling. So the
-- gate has to be written into that function by hand or it is not written anywhere — and this is the
-- content that actually costs money, roughly 85c per tracked flight across its life.

reset role;
insert into public.flights (id, couple_id, flight_number_iata, status, scheduled_out, tracking_enabled)
values
  ('22222222-9999-0000-0000-0000000000a1', 'ffffffff-9999-0000-0000-0000000000a1',
   'QF1', 'scheduled', now() + interval '2 days', false),
  ('22222222-9999-0000-0000-0000000000b1', 'ffffffff-9999-0000-0000-0000000000b1',
   'QF2', 'scheduled', now() + interval '2 days', false);

set local role authenticated;
set local request.jwt.claims = '{"sub":"eeeeeeee-9999-0000-0000-00000000000c","role":"authenticated"}';

select is(
  (select public.enable_flight_tracking('22222222-9999-0000-0000-0000000000b1') ->> 'reason'),
  'subscription_required',
  'a lapsed couple cannot start tracking a flight — the priciest thing in the app'
);

-- The refusal has to actually withhold the polling, not merely report that it did.
reset role;
select is(
  (select tracking_enabled from public.flights where id = '22222222-9999-0000-0000-0000000000b1'),
  false,
  'and the flight is left untracked'
);

-- Nor may the refusal quietly spend one of the month's slots on the way past.
select is(
  (select count(*)::int from public.flight_additions
   where flight_id = '22222222-9999-0000-0000-0000000000b1'),
  0,
  'and no slot is spent by the attempt'
);

-- The other direction, because a gate that refuses everybody is the more expensive mistake.
set local role authenticated;
set local request.jwt.claims = '{"sub":"eeeeeeee-9999-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select public.enable_flight_tracking('22222222-9999-0000-0000-0000000000a1') ->> 'enabled'),
  'true',
  'the non-paying partner of a paying couple still can — coverage is the couple''s'
);

reset role;
select * from finish();
rollback;
