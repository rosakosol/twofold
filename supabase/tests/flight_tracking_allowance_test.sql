-- The monthly live-tracking allowance.
--
-- This limit is the one commercial control on the app's largest variable cost: tracking a flight
-- to the gate is ~85c of AeroAPI, against ~2c to add it. Every way it can be wrong costs real
-- money or takes something from a paying couple, and none of it is visible from the app:
--
--   * A flight charging twice. `tracking_enabled` is cleared by the system in the ordinary course
--     of things — two hours after arrival, on dissolution, on a lapsed subscription — so any path
--     that re-enables a flight must not spend a second slot for it.
--   * A deleted flight refunding its slot, which is the whole reason flight_additions is
--     append-only and outlives the flight it recorded.
--   * A slot spent on a flight that has already landed, which buys the couple nothing.
--   * Someone else's flight being enabled at your expense.

begin;
select plan(15);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-4444-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@track.test', 'x', now(), now(), now()),
  ('bbbbbbbb-4444-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@track.test', 'x', now(), now(), now()),
  ('dddddddd-4444-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd@track.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name) values
  ('aaaaaaaa-4444-0000-0000-000000000001', 'Ada'),
  ('bbbbbbbb-4444-0000-0000-000000000002', 'Mel'),
  ('dddddddd-4444-0000-0000-000000000004', 'Dev')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-4444-0000-0000-000000000003', 'aaaaaaaa-4444-0000-0000-000000000001', 'bbbbbbbb-4444-0000-0000-000000000002');

-- MARK: the limits themselves

select is(public.flight_limit_for_tier('plus'), 2, 'Plus tracks 2 flights a month');
select is(public.flight_limit_for_tier('premium'), 5, 'Premium tracks 5');
-- A couple with no tier recorded gets the free tier's allowance, never zero and never premium's.
select is(public.flight_limit_for_tier(null), 2, 'an unknown tier falls back to the Plus allowance');

-- MARK: spending the allowance

-- Four untracked flights, as add-flight now writes them once a couple is over the limit.
insert into public.flights (id, couple_id, status, tracking_enabled, cancelled, diverted, shared)
values
  ('f1111111-4444-0000-0000-000000000011', 'cccccccc-4444-0000-0000-000000000003', 'scheduled', false, false, false, true),
  ('f2222222-4444-0000-0000-000000000022', 'cccccccc-4444-0000-0000-000000000003', 'scheduled', false, false, false, true),
  ('f3333333-4444-0000-0000-000000000033', 'cccccccc-4444-0000-0000-000000000003', 'scheduled', false, false, false, true),
  ('f4444444-4444-0000-0000-000000000044', 'cccccccc-4444-0000-0000-000000000003', 'arrived',   false, false, false, true);

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-4444-0000-0000-000000000001"}';

select is(
  (public.enable_flight_tracking('f1111111-4444-0000-0000-000000000011') ->> 'enabled')::boolean,
  true,
  'the first flight of the month can be tracked'
);
select is(
  (public.enable_flight_tracking('f2222222-4444-0000-0000-000000000022') ->> 'enabled')::boolean,
  true,
  'and the second, which is the whole Plus allowance'
);
select is(
  public.enable_flight_tracking('f3333333-4444-0000-0000-000000000033') ->> 'reason',
  'limit_reached',
  'the third is refused'
);

reset role;
select is(
  (select tracking_enabled from public.flights where id = 'f3333333-4444-0000-0000-000000000033'),
  false,
  'and is genuinely left untracked rather than merely reported as refused'
);
select is(
  (select count(*)::integer from public.flight_additions where couple_id = 'cccccccc-4444-0000-0000-000000000003'),
  2,
  'exactly two slots were spent'
);

-- MARK: a flight spends one slot, ever

-- The system clears tracking two hours after arrival. Re-enabling must not charge again.
update public.flights set tracking_enabled = false where id = 'f1111111-4444-0000-0000-000000000011';

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-4444-0000-0000-000000000001"}';
select is(
  (public.enable_flight_tracking('f1111111-4444-0000-0000-000000000011') ->> 'enabled')::boolean,
  true,
  'a flight that already spent a slot can be re-enabled even at the limit'
);

reset role;
select is(
  (select count(*)::integer from public.flight_additions where couple_id = 'cccccccc-4444-0000-0000-000000000003'),
  2,
  'and spends nothing further — one slot per flight, ever'
);

-- MARK: a landed flight buys nothing

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-4444-0000-0000-000000000002"}';
select is(
  public.enable_flight_tracking('f4444444-4444-0000-0000-000000000044') ->> 'reason',
  'flight_over',
  'a flight that has already arrived cannot be tracked'
);

-- MARK: deleting never refunds

reset role;
delete from public.flights where id = 'f2222222-4444-0000-0000-000000000022';
select is(
  public.flights_used_this_month('cccccccc-4444-0000-0000-000000000003'),
  2,
  'deleting a tracked flight does not refund its slot'
);
select is(
  (select flight_id from public.flight_additions where flight_id is null limit 1),
  null,
  'the ledger row outlives the flight, with its reference nulled'
);

-- MARK: and it is the couple's allowance, not anyone else's

set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-4444-0000-0000-000000000004"}';
select throws_ok(
  $$ select public.enable_flight_tracking('f3333333-4444-0000-0000-000000000033') $$,
  '42501',
  'No such flight',
  'a stranger cannot spend a couple''s allowance on their flight'
);

-- Premium gets the larger allowance, on the same couple, with two slots already spent.
reset role;
update public.profiles set subscription_active = true, subscription_tier = 'premium'
where id = 'aaaaaaaa-4444-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-4444-0000-0000-000000000001"}';
select is(
  (public.enable_flight_tracking('f3333333-4444-0000-0000-000000000033') ->> 'enabled')::boolean,
  true,
  'upgrading to Premium opens the allowance back up'
);

select * from finish();
rollback;
