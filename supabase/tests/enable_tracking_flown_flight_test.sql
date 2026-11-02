-- A flight that has already flown spends no tracking slot, even when its status never moved
-- (3-flights-NEW-1).
--
-- An untracked flight gets no status updates, so a flight saved without tracking still says
-- 'scheduled' after it has landed. `enable_flight_tracking` decided "flight over" from the status
-- and the cancelled/diverted flags alone, so for that flight it switched tracking on and recorded a
-- `flight_additions` row: one of the couple's monthly slots spent on a flight that was over.
-- The function's own comment says a flight that has already arrived spends none.
--
-- The clock decides now as well, using the same best-known time the app uses
-- (`Flight.bestArrival ?? Flight.bestDeparture`): a flight whose arrival has passed is over, and so
-- is one with no arrival time whose departure has passed. A flight still in the air is not over.

begin;
select plan(7);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-5555-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@flown.test', 'x', now(), now(), now()),
  ('bbbbbbbb-5555-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@flown.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name) values
  ('aaaaaaaa-5555-0000-0000-000000000001', 'Ada'),
  ('bbbbbbbb-5555-0000-0000-000000000002', 'Mel')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-5555-0000-0000-000000000003', 'aaaaaaaa-5555-0000-0000-000000000001', 'bbbbbbbb-5555-0000-0000-000000000002');

-- Subscribed, so the subscription gate is not the answer any of these reads.
update public.profiles set subscription_active = true
where id in ('aaaaaaaa-5555-0000-0000-000000000001', 'bbbbbbbb-5555-0000-0000-000000000002');

insert into public.flights (id, couple_id, status, tracking_enabled, cancelled, diverted, shared, scheduled_out, scheduled_in)
values
  -- Flew ten days ago, still marked scheduled.
  ('f1111111-5555-0000-0000-000000000011', 'cccccccc-5555-0000-0000-000000000003', 'scheduled', false, false, false, true,
    now() - interval '10 days 8 hours', now() - interval '10 days'),
  -- No arrival time recorded; left two days ago.
  ('f2222222-5555-0000-0000-000000000022', 'cccccccc-5555-0000-0000-000000000003', 'scheduled', false, false, false, true,
    now() - interval '2 days', null),
  -- In the air right now: left an hour ago, lands in three.
  ('f3333333-5555-0000-0000-000000000033', 'cccccccc-5555-0000-0000-000000000003', 'scheduled', false, false, false, true,
    now() - interval '1 hour', now() + interval '3 hours'),
  -- Next week.
  ('f4444444-5555-0000-0000-000000000044', 'cccccccc-5555-0000-0000-000000000003', 'scheduled', false, false, false, true,
    now() + interval '7 days', now() + interval '7 days 9 hours');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-5555-0000-0000-000000000001"}';

select is(
  public.enable_flight_tracking('f1111111-5555-0000-0000-000000000011')->>'reason',
  'flight_over',
  'a flight whose arrival has passed is over, whatever its status still says'
);
select is(
  public.enable_flight_tracking('f2222222-5555-0000-0000-000000000022')->>'reason',
  'flight_over',
  'with no arrival time, a departure two days ago is over'
);
select is(
  (public.enable_flight_tracking('f3333333-5555-0000-0000-000000000033')->>'enabled')::boolean,
  true,
  'a flight still in the air can still be tracked'
);
select is(
  (public.enable_flight_tracking('f4444444-5555-0000-0000-000000000044')->>'enabled')::boolean,
  true,
  'and so can one next week'
);

reset role;

select is(
  (select tracking_enabled from public.flights where id = 'f1111111-5555-0000-0000-000000000011'),
  false,
  'the flown flight was not switched on'
);
select is(
  (select count(*)::int from public.flight_additions
   where flight_id in ('f1111111-5555-0000-0000-000000000011', 'f2222222-5555-0000-0000-000000000022')),
  0,
  'and no slot was spent on either flown flight'
);
select is(
  (select count(*)::int from public.flight_additions where couple_id = 'cccccccc-5555-0000-0000-000000000003'),
  2,
  'the two that could be tracked spent one each'
);

select * from finish();
rollback;
