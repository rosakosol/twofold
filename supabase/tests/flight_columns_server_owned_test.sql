-- A client can change which trip a flight belongs to, who is on it and whether it is shared. It
-- cannot switch tracking on, or rewrite the fields AeroAPI owns, because either one starts or
-- prolongs paid polling without passing the subscription and allowance checks in
-- enable_flight_tracking. See 20261114002000.

begin;
select plan(10);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-7777-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@fcols.test', 'x', now(), now(), now()),
  ('bbbbbbbb-7777-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@fcols.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name) values
  ('aaaaaaaa-7777-0000-0000-000000000001', 'Ada'),
  ('bbbbbbbb-7777-0000-0000-000000000002', 'Mel')
on conflict (id) do update set first_name = excluded.first_name;

-- Lapsed: neither partner is subscribed. This is the couple enable_flight_tracking refuses.
update public.profiles set subscription_active = false
where id in ('aaaaaaaa-7777-0000-0000-000000000001', 'bbbbbbbb-7777-0000-0000-000000000002');

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-7777-0000-0000-000000000003', 'aaaaaaaa-7777-0000-0000-000000000001', 'bbbbbbbb-7777-0000-0000-000000000002');

insert into public.flights (id, couple_id, status, tracking_enabled, cancelled, diverted, shared, created_by, fa_flight_id)
values
  ('f1111111-7777-0000-0000-000000000011', 'cccccccc-7777-0000-0000-000000000003', 'scheduled', false, false, false, true, 'aaaaaaaa-7777-0000-0000-000000000001', 'UAL1-1'),
  ('f2222222-7777-0000-0000-000000000022', 'cccccccc-7777-0000-0000-000000000003', 'arrived',   true,  false, false, true, 'aaaaaaaa-7777-0000-0000-000000000001', 'UAL2-2');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-000000000001"}';

-- The front door refuses, which is the behaviour the PATCH below used to walk around.
select is(
  public.enable_flight_tracking('f1111111-7777-0000-0000-000000000011') ->> 'reason',
  'subscription_required',
  'a lapsed couple is refused by enable_flight_tracking'
);

select throws_ok(
  $$update public.flights set tracking_enabled = true where id = 'f1111111-7777-0000-0000-000000000011'$$,
  '42501', null,
  'a client cannot switch tracking on directly'
);

select throws_ok(
  $$update public.flights set status = 'scheduled', scheduled_out = now() + interval '3 days' where id = 'f2222222-7777-0000-0000-000000000022'$$,
  '42501', null,
  'a client cannot reopen a landed, still-tracked flight for more polling'
);

select throws_ok(
  $$update public.flights set fa_flight_id = 'DAL9-9' where id = 'f2222222-7777-0000-0000-000000000022'$$,
  '42501', null,
  'a client cannot point a tracked slot at a different flight'
);

-- A bundled PATCH fails whole rather than applying its harmless half.
select throws_ok(
  $$update public.flights set traveler_ids = array['aaaaaaaa-7777-0000-0000-000000000001'::uuid], tracking_enabled = true where id = 'f1111111-7777-0000-0000-000000000011'$$,
  '42501', null,
  'an allowed column does not carry a forbidden one through'
);

-- What the app actually writes still works.
select lives_ok(
  $$update public.flights set traveler_ids = array['aaaaaaaa-7777-0000-0000-000000000001'::uuid], trip_id = null where id = 'f1111111-7777-0000-0000-000000000011'$$,
  'the app can still set travelers and the trip'
);
select lives_ok(
  $$update public.flights set shared = true where id = 'f1111111-7777-0000-0000-000000000011'$$,
  'and sharing stays the owner''s to set'
);

reset role;

select is(
  (select tracking_enabled from public.flights where id = 'f1111111-7777-0000-0000-000000000011'),
  false,
  'the flight was genuinely left untracked'
);

-- Server writers are untouched: the definer path and service_role.
update public.profiles set subscription_active = true where id = 'aaaaaaaa-7777-0000-0000-000000000001';
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-7777-0000-0000-000000000001"}';
select is(
  (public.enable_flight_tracking('f1111111-7777-0000-0000-000000000011') ->> 'enabled')::boolean,
  true,
  'once subscribed, enable_flight_tracking still turns tracking on'
);
reset role;

set local role service_role;
select lives_ok(
  $$update public.flights set status = 'landed', tracking_enabled = false where id = 'f2222222-7777-0000-0000-000000000022'$$,
  'service_role (the refresh functions) still writes tracking state'
);
reset role;

select * from finish();
rollback;
