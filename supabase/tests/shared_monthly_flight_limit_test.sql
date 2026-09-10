-- The shared monthly flight limit.
--
-- The three properties that are easy to implement wrongly, each asserted against the thing that
-- would go wrong: a per-person count would double a couple's allowance, a `count(*) from flights`
-- would refund a deleted flight, and a rolling window would not reset on the 1st.

begin;
select plan(14);

create extension if not exists pgtap;

-- Two people, one couple.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@limit.test', 'x', now(), now()),
  ('aaaaaaaa-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@limit.test', 'x', now(), now()),
  -- Nobody's partner. Present so the membership checks below have something real to refuse.
  ('aaaaaaaa-0000-0000-0000-00000000000e', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'outsider@limit.test', 'x', now(), now())
on conflict do nothing;

insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('cccccccc-0000-0000-0000-00000000000c', 'aaaaaaaa-0000-0000-0000-00000000000a', 'aaaaaaaa-0000-0000-0000-00000000000b', 'active');

-- Plus by default: no active subscription resolves to 'plus', which is the free-tier floor.
select is(public.flight_limit_for_tier('plus'), 5, 'plus allows 5 a month');
select is(public.flight_limit_for_tier('premium'), 20, 'premium allows 20 a month');
select is(public.flight_limit_for_tier(null), 5, 'an unknown tier falls back to the smaller allowance');

select is(public.flights_used_this_month('cccccccc-0000-0000-0000-00000000000c'), 0, 'a new couple has used nothing');

-- Spend the Plus allowance across BOTH partners. Per-person counting would let this reach ten.
select public.record_flight_addition('cccccccc-0000-0000-0000-00000000000c', null, 'aaaaaaaa-0000-0000-0000-00000000000a');
select public.record_flight_addition('cccccccc-0000-0000-0000-00000000000c', null, 'aaaaaaaa-0000-0000-0000-00000000000a');
select public.record_flight_addition('cccccccc-0000-0000-0000-00000000000c', null, 'aaaaaaaa-0000-0000-0000-00000000000b');
select public.record_flight_addition('cccccccc-0000-0000-0000-00000000000c', null, 'aaaaaaaa-0000-0000-0000-00000000000b');
select public.record_flight_addition('cccccccc-0000-0000-0000-00000000000c', null, 'aaaaaaaa-0000-0000-0000-00000000000a');

select is(public.flights_used_this_month('cccccccc-0000-0000-0000-00000000000c'), 5, 'both partners draw on one shared allowance');

-- A deleted flight still counts. This is the one a row count gets wrong.
insert into public.flights (id, couple_id, cancelled, diverted, status, tracking_enabled, shared, pre_departure_notified, traveler_ids, arrival_1h_notified, arrival_30m_notified)
values ('ffffffff-0000-0000-0000-00000000000f', 'cccccccc-0000-0000-0000-00000000000c', false, false, 'scheduled', true, true, false, '{}', false, false);
insert into public.flight_additions (couple_id, flight_id, added_by)
values ('cccccccc-0000-0000-0000-00000000000c', 'ffffffff-0000-0000-0000-00000000000f', 'aaaaaaaa-0000-0000-0000-00000000000a');

delete from public.flights where id = 'ffffffff-0000-0000-0000-00000000000f';

select is(public.flights_used_this_month('cccccccc-0000-0000-0000-00000000000c'), 6, 'deleting the flight does not hand the slot back');
select is(
  (select count(*)::integer from public.flight_additions where couple_id = 'cccccccc-0000-0000-0000-00000000000c' and flight_id is null),
  6, 'the ledger row survives the flight, with its reference nulled'
);

-- Last month's flights don't count against this one.
insert into public.flight_additions (couple_id, flight_id, added_by, added_at)
values ('cccccccc-0000-0000-0000-00000000000c', null, 'aaaaaaaa-0000-0000-0000-00000000000a',
        date_trunc('month', now() at time zone 'utc') - interval '1 day');

select is(public.flights_used_this_month('cccccccc-0000-0000-0000-00000000000c'), 6, 'the count is this calendar month only');

-- ---------------------------------------------------------------------------
-- What a client can actually reach
-- ---------------------------------------------------------------------------
--
-- Everything above runs as the owner, which is the one role that proves nothing about access. The
-- limit is only real if the app can read it and cannot write it.

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}';

-- The numbers the app puts on screen, in one round trip. `tier` is left out of the comparison
-- because it depends on subscription state this test does not set up; the two fields that decide
-- whether a search is refused are asserted exactly.
select is(
  public.flight_allowance('cccccccc-0000-0000-0000-00000000000c') - 'tier',
  jsonb_build_object('limit', 5, 'used', 6),
  'a member reads their couple''s limit and usage'
);

select is(
  (select count(*)::integer from public.flight_additions),
  7, 'a member can read their own ledger, all of it, including last month''s'
);

-- The one that matters: a client cannot write its own ledger. If it could, it could also decline
-- to, and the limit would be advisory.
select throws_ok(
  $$ select public.record_flight_addition('cccccccc-0000-0000-0000-00000000000c', null, 'aaaaaaaa-0000-0000-0000-00000000000a') $$,
  '42501',
  null,
  'a client cannot record its own flight additions'
);

-- ...but the edge function still can, or nothing would ever be recorded. Revoking from PUBLIC
-- takes the grant away from service_role too, so it has to be given back explicitly; this is the
-- half that fails if that grant is dropped.
set local role service_role;
select lives_ok(
  $$ select public.record_flight_addition('cccccccc-0000-0000-0000-00000000000c', null, 'aaaaaaaa-0000-0000-0000-00000000000a') $$,
  'the edge function can record an addition'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-00000000000e","role":"authenticated"}';

select throws_ok(
  $$ select public.flight_allowance('cccccccc-0000-0000-0000-00000000000c') $$,
  '42501',
  null,
  'a stranger cannot read a couple''s allowance'
);

select is(
  (select count(*)::integer from public.flight_additions),
  0, 'a stranger sees no ledger rows at all'
);

reset role;
select * from finish();
rollback;
