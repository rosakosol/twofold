-- A write that changes nothing on a flight is not a write (no new row version, no realtime event).
--
-- Every change to a `flights` row goes out over realtime, and each one makes both partners' phones
-- rebuild their whole widget snapshot. Some writes changed nothing: the live-position pass writes
-- the last known position onto every couple's copy of a flight every minute, and through an
-- oceanic coverage gap that is the same position for hours. `touch_updated_at` then stamped a new
-- updated_at, so the identical write still became a change.
--
-- `suppress_redundant_updates_trigger` drops an update whose new row equals the old one. It has to
-- run before `trg_flights_touch` (triggers fire in name order), or the stamp makes every row differ.

begin;
select plan(5);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-8888-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@noop-writes.test', 'x', now(), now(), now()),
  ('bbbbbbbb-8888-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@noop-writes.test', 'x', now(), now(), now());

insert into public.couples (id, partner_a_id, partner_b_id)
values ('cccccccc-8888-0000-0000-000000000003', 'aaaaaaaa-8888-0000-0000-000000000001', 'bbbbbbbb-8888-0000-0000-000000000002');

insert into public.flights (id, couple_id, status, tracking_enabled, position_latitude, position_longitude, position_updated_at, updated_at)
values ('f0000000-8888-0000-0000-000000000001', 'cccccccc-8888-0000-0000-000000000003', 'in_air', true,
  -10.5, 150.25, '2026-11-01T00:00:00Z', '2026-11-01T00:00:00Z');

create temporary table before as
select ctid as row_version, updated_at from public.flights where id = 'f0000000-8888-0000-0000-000000000001';

-- What the live-position pass writes when the mirrors have nothing newer.
update public.flights
set position_latitude = -10.5, position_longitude = 150.25, position_updated_at = '2026-11-01T00:00:00Z'
where id = 'f0000000-8888-0000-0000-000000000001';

select is(
  (select ctid from public.flights where id = 'f0000000-8888-0000-0000-000000000001'),
  (select row_version from before),
  'rewriting the same position leaves the row as it was'
);
select is(
  (select updated_at from public.flights where id = 'f0000000-8888-0000-0000-000000000001'),
  '2026-11-01T00:00:00Z'::timestamptz,
  'and does not stamp it updated'
);

update public.flights set position_latitude = -10.75 where id = 'f0000000-8888-0000-0000-000000000001';

select isnt(
  (select ctid from public.flights where id = 'f0000000-8888-0000-0000-000000000001'),
  (select row_version from before),
  'a real change is still written'
);
select is(
  (select updated_at from public.flights where id = 'f0000000-8888-0000-0000-000000000001'),
  now(),
  'and still stamped updated'
);

select is(
  (select array_agg(tgname::text order by tgname::text) from pg_trigger
   where tgrelid = 'public.flights'::regclass and not tgisinternal and tgtype & 16 = 16),
  array['trg_flights_a_skip_unchanged', 'trg_flights_guard_server_columns', 'trg_flights_touch'],
  'the skip runs before the other update triggers'
);

select * from finish();
rollback;
