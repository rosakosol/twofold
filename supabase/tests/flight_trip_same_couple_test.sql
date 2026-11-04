-- A flight can only be linked to a trip of its own couple.
--
-- `flights.trip_id` is checked by its foreign key, which proves the trip exists and nothing else,
-- and foreign-key checks do not consult RLS. `trip_id` is on the client's update allowlist
-- (20261114002000) and add-flight inserts whatever `tripId` it is sent, as service_role. So any
-- couple member could link their flight to any trip id at all, including another couple's.

begin;
select plan(6);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-8888-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@trip-link.test', 'x', now(), now(), now()),
  ('bbbbbbbb-8888-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@trip-link.test', 'x', now(), now(), now()),
  ('dddddddd-8888-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd@trip-link.test', 'x', now(), now(), now()),
  ('eeeeeeee-8888-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'e@trip-link.test', 'x', now(), now(), now());

insert into public.couples (id, partner_a_id, partner_b_id) values
  ('cccccccc-8888-0000-0000-000000000003', 'aaaaaaaa-8888-0000-0000-000000000001', 'bbbbbbbb-8888-0000-0000-000000000002'),
  ('cccccccc-8888-0000-0000-000000000006', 'dddddddd-8888-0000-0000-000000000004', 'eeeeeeee-8888-0000-0000-000000000005');

insert into public.places (id, city, country, latitude, longitude)
values ('99999999-8888-0000-0000-000000000009', 'Trip Link Test', 'Nowhere', 0, 0);

insert into public.trips (id, couple_id, origin_id, destination_id, departure_at, arrival_at, category) values
  ('11111111-8888-0000-0000-000000000011', 'cccccccc-8888-0000-0000-000000000003',
   '99999999-8888-0000-0000-000000000009', '99999999-8888-0000-0000-000000000009', now(), now() + interval '1 day', 'together'),
  ('22222222-8888-0000-0000-000000000022', 'cccccccc-8888-0000-0000-000000000006',
   '99999999-8888-0000-0000-000000000009', '99999999-8888-0000-0000-000000000009', now(), now() + interval '1 day', 'together');

insert into public.flights (id, couple_id, created_by, status, tracking_enabled, cancelled, diverted, shared)
values ('f1111111-8888-0000-0000-000000000011', 'cccccccc-8888-0000-0000-000000000003',
        'aaaaaaaa-8888-0000-0000-000000000001', 'scheduled', false, false, false, true);

-- MARK: as the app

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-8888-0000-0000-000000000001","role":"authenticated"}';

select lives_ok(
  $$ update public.flights set trip_id = '11111111-8888-0000-0000-000000000011' where id = 'f1111111-8888-0000-0000-000000000011' $$,
  'a member links their flight to their own trip'
);
select lives_ok(
  $$ update public.flights set trip_id = null where id = 'f1111111-8888-0000-0000-000000000011' $$,
  'and unlinks it'
);
select throws_ok(
  $$ update public.flights set trip_id = '22222222-8888-0000-0000-000000000022' where id = 'f1111111-8888-0000-0000-000000000011' $$,
  '23503', null,
  'but cannot link it to another couple''s trip'
);

reset role;

-- MARK: as add-flight, which inserts as the service role

set local role service_role;
select throws_ok(
  $$ insert into public.flights (couple_id, created_by, status, tracking_enabled, cancelled, diverted, shared, trip_id)
     values ('cccccccc-8888-0000-0000-000000000003', 'aaaaaaaa-8888-0000-0000-000000000001', 'scheduled', false, false, false, true,
             '22222222-8888-0000-0000-000000000022') $$,
  '23503', null,
  'a flight cannot be saved onto another couple''s trip'
);
select lives_ok(
  $$ insert into public.flights (couple_id, created_by, status, tracking_enabled, cancelled, diverted, shared, trip_id)
     values ('cccccccc-8888-0000-0000-000000000003', 'aaaaaaaa-8888-0000-0000-000000000001', 'scheduled', false, false, false, true,
             '11111111-8888-0000-0000-000000000011') $$,
  'only onto its own'
);
reset role;

-- The trip's own deletion still unlinks, through the foreign key's `on delete set null`.
delete from public.trips where id = '11111111-8888-0000-0000-000000000011';
select is(
  (select count(*)::integer from public.flights where trip_id = '11111111-8888-0000-0000-000000000011'),
  0, 'deleting a trip still unlinks its flights'
);

select * from finish();
rollback;
