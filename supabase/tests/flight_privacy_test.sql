-- `flights.shared = false` means "my partner cannot see this flight" — on every policy, not just
-- the read ones.
--
-- 20260712110000 taught four SELECT policies about the toggle and left six other flight-scoped
-- policies testing couple membership alone. 20260916000000 closes them. The two that mattered were
-- `flights_update_members` and `flights_delete_members`: unlike the child tables, whose policies
-- happen to inherit the rule because RLS applies inside their `exists (select ... from flights)`
-- subqueries, those two test `couple_id` on the flights row directly and had nothing to inherit.
--
-- That is why the last section below uses statements with NO `where` clause. It is not an exotic
-- shape chosen to make a point — it is the only shape that actually exercises the UPDATE and DELETE
-- policies. Postgres applies SELECT policies to an UPDATE or DELETE whenever the statement needs to
-- read the row, which any column reference in a `where` clause causes, so
-- `delete from flights where id = $1` was already stopped by `flights_select_members` and proves
-- nothing about `flights_delete_members`. Measured against the pre-migration schema on a local
-- stack, the unfiltered forms gave: `update public.flights set shared = true` → 2 rows, the private
-- flight readable on the very next select; `delete from public.flights` → the private flight
-- destroyed, cascading its events, preferences and documents. Both are pinned harmless here.
--
-- Every assertion runs as ONE role — the partner who created neither the shared nor the private
-- flight — because the point is not "some session is refused" but "this session is refused the
-- private rows and still allowed everything else". The "still allowed" half is load-bearing: a
-- policy that denied everything would pass a privacy test and break the app.

begin;
select plan(21);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-4444-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@flightprivacy.test', 'x', now(), now(), now()),
  ('bbbbbbbb-4444-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@flightprivacy.test', 'x', now(), now(), now());

-- A trigger on auth.users already created these rows, so this fills in the fields the
-- tests care about rather than inserting fresh.
insert into public.profiles (id, first_name) values
  ('aaaaaaaa-4444-0000-0000-000000000001', 'Ann'),
  ('bbbbbbbb-4444-0000-0000-000000000002', 'Ben')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('cccccccc-4444-0000-0000-000000000003',
        'aaaaaaaa-4444-0000-0000-000000000001',
        'bbbbbbbb-4444-0000-0000-000000000002',
        'active');

-- Any seeded place will do — `trips` needs origin and destination FKs and nothing here looks at
-- geography.
insert into public.trips (id, couple_id, origin_id, destination_id, departure_at, arrival_at, category)
select 'dddddddd-4444-0000-0000-000000000004', 'cccccccc-4444-0000-0000-000000000003',
       p.id, p.id, now(), now() + interval '1 day', 'together'
from public.places p limit 1;

-- Four flights, all in the one couple, all linked to the one trip (flight_updates_select_members
-- reaches the couple through `flights.trip_id`, so an unlinked flight would make that section
-- vacuous):
--   ...11  Ann's PRIVATE flight — the row Ben must never read, write, or destroy
--   ...22  Ann's SHARED flight  — the control: everything normal must still work on it
--   ...55  Ben's own PRIVATE    — proves the rule turns on visibility, and that a creator keeps
--                                 full control of their own private flight
--   ...88  Ben's own SHARED     — the flight Ben is allowed to un-share
-- fa_flight_id stands in as a readable label; no policy reads it.
insert into public.flights (id, couple_id, created_by, trip_id, shared, fa_flight_id)
values
  ('11111111-4444-0000-0000-000000000011', 'cccccccc-4444-0000-0000-000000000003', 'aaaaaaaa-4444-0000-0000-000000000001', 'dddddddd-4444-0000-0000-000000000004', false, 'ANN-PRIVATE'),
  ('22222222-4444-0000-0000-000000000022', 'cccccccc-4444-0000-0000-000000000003', 'aaaaaaaa-4444-0000-0000-000000000001', 'dddddddd-4444-0000-0000-000000000004', true,  'ANN-SHARED'),
  ('55555555-4444-0000-0000-000000000055', 'cccccccc-4444-0000-0000-000000000003', 'bbbbbbbb-4444-0000-0000-000000000002', 'dddddddd-4444-0000-0000-000000000004', false, 'BEN-PRIVATE'),
  ('88888888-4444-0000-0000-000000000088', 'cccccccc-4444-0000-0000-000000000003', 'bbbbbbbb-4444-0000-0000-000000000002', 'dddddddd-4444-0000-0000-000000000004', true,  'BEN-SHARED');

-- The dual-parent document the `case` in flight_documents' policies exists for: attached to Ann's
-- private flight AND to the trip that flight belongs to. `flight_documents_one_parent` forbids that
-- shape today, so it is dropped for the duration of this (rolled-back) transaction. That is not
-- cheating the test — it is the test. The constraint is the only thing that stood between the old
-- `or`-shaped policy and a real leak, and it is one `alter table` away from being dropped the first
-- time someone wants a boarding pass to appear on both a flight and its trip. With `or` the trip
-- branch answers first and privacy is lost, because a trip has no privacy toggle to consult.
alter table public.flight_documents drop constraint flight_documents_one_parent;

insert into public.flight_documents (id, flight_id, trip_id, uploaded_by, doc_type, file_path)
values
  ('33333333-4444-0000-0000-000000000033', '11111111-4444-0000-0000-000000000011', null, 'aaaaaaaa-4444-0000-0000-000000000001', 'boarding_pass', 'c/f/private.pdf'),
  ('66666666-4444-0000-0000-000000000066', '11111111-4444-0000-0000-000000000011', 'dddddddd-4444-0000-0000-000000000004', 'aaaaaaaa-4444-0000-0000-000000000001', 'itinerary', 'c/f/dual.pdf'),
  ('77777777-4444-0000-0000-000000000077', '22222222-4444-0000-0000-000000000022', null, 'aaaaaaaa-4444-0000-0000-000000000001', 'boarding_pass', 'c/f/shared.pdf');

-- Traveler self-reported notes. Inserted as postgres, which bypasses RLS — this table's insert
-- policy is not what is under test, its select policy is.
insert into public.flight_updates (id, flight_id, kind, note, created_by)
values
  ('44444444-4444-0000-0000-000000000044', '11111111-4444-0000-0000-000000000011', 'custom', 'on the private flight', 'aaaaaaaa-4444-0000-0000-000000000001'),
  ('99999999-4444-0000-0000-000000000099', '22222222-4444-0000-0000-000000000022', 'custom', 'on the shared flight',  'aaaaaaaa-4444-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- Everything below is Ben, the partner. Ann's private flight is the row he must not reach.
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', 'bbbbbbbb-4444-0000-0000-000000000002', true);

select results_eq(
  $$select fa_flight_id from public.flights order by fa_flight_id$$,
  $$values ('ANN-SHARED'::text), ('BEN-PRIVATE'), ('BEN-SHARED')$$,
  'the partner sees the shared flight and both of their own, and not the private one they did not create'
);

-- ---------------------------------------------------------------------------
-- UPDATE
-- ---------------------------------------------------------------------------

-- `setFlightTrip`/`setFlightTravelers` always filter by id. Refused before the migration too (via
-- the SELECT policy — see the header), and it must stay refused.
with u as (
  update public.flights set traveler_ids = array['bbbbbbbb-4444-0000-0000-000000000002'::uuid]
  where id = '11111111-4444-0000-0000-000000000011'
  returning 1
)
select is((select count(*)::int from u), 0, 'the partner cannot update a private flight they did not create');

-- The WITH CHECK half. Un-sharing someone else's flight produces a candidate row that is neither
-- shared nor theirs, so the check rejects it — an error, not a silent no-op, which is why this is
-- throws_ok and not a row count.
--
-- The filtered form was already refused before 20260916000000, for a reason worth writing down
-- because it is the same rule that hides the two real holes: a `where` clause makes Postgres apply
-- SELECT policies to the NEW row as well as the existing one, and the new row (not shared, not
-- Ben's) fails `flights_select_members`. So this assertion pins a property rather than proving a
-- fix — which is exactly why the unfiltered form follows it. That one reads no columns, gets no
-- help from any SELECT policy, and before the migration silently un-shared Ann's flight.
select throws_ok(
  $$update public.flights set shared = false where id = '22222222-4444-0000-0000-000000000022'$$,
  '42501',
  null,
  'the partner cannot un-share a flight they did not create'
);

select throws_ok(
  $$update public.flights set shared = false$$,
  '42501',
  null,
  'nor by way of an unfiltered un-share, which no SELECT policy would have caught'
);

select is(
  (select shared from public.flights where id = '22222222-4444-0000-0000-000000000022'),
  true,
  'and the shared flight is still shared afterwards'
);

-- The same statement on a flight they did create passes the check on `created_by = auth.uid()`.
-- If this failed, the migration would have made the privacy toggle unusable by its own owner.
update public.flights set shared = false where id = '88888888-4444-0000-0000-000000000088';
select is(
  (select shared from public.flights where id = '88888888-4444-0000-0000-000000000088'),
  false,
  'the creator can still un-share their own flight'
);

with u as (
  update public.flights set traveler_ids = array['bbbbbbbb-4444-0000-0000-000000000002'::uuid]
  where id = '22222222-4444-0000-0000-000000000022'
  returning 1
)
select is((select count(*)::int from u), 1, 'the partner can still update a shared flight');

with u as (
  update public.flights set traveler_ids = array['bbbbbbbb-4444-0000-0000-000000000002'::uuid]
  where id = '55555555-4444-0000-0000-000000000055'
  returning 1
)
select is((select count(*)::int from u), 1, 'the creator can still update their own private flight');

-- ---------------------------------------------------------------------------
-- flight_updates — dormant table, same rule.
-- ---------------------------------------------------------------------------
select results_eq(
  $$select note from public.flight_updates order by note$$,
  $$values ('on the shared flight'::text)$$,
  'flight_updates on a private flight are not readable by the partner, and shared ones still are'
);

-- ---------------------------------------------------------------------------
-- flight_documents — including the dual-parent row the `case` exists for.
-- ---------------------------------------------------------------------------
select results_eq(
  $$select file_path from public.flight_documents order by file_path$$,
  $$values ('c/f/shared.pdf'::text)$$,
  'the partner reads only the shared flight''s document — not the private one, and not the dual-parented one'
);

select is(
  (select count(*)::int from public.flight_documents where id = '66666666-4444-0000-0000-000000000066'),
  0,
  'the dual-parent document on a private flight is not reachable through its trip branch'
);

select throws_ok(
  $$insert into public.flight_documents (flight_id, uploaded_by, doc_type, file_path)
    values ('11111111-4444-0000-0000-000000000011', 'bbbbbbbb-4444-0000-0000-000000000002', 'other', 'c/f/sneak.pdf')$$,
  '42501',
  null,
  'the partner cannot attach a document to a private flight they did not create'
);

insert into public.flight_documents (flight_id, uploaded_by, doc_type, file_path)
values ('22222222-4444-0000-0000-000000000022', 'bbbbbbbb-4444-0000-0000-000000000002', 'other', 'c/f/ben.pdf');
select is(
  (select count(*)::int from public.flight_documents where file_path = 'c/f/ben.pdf'),
  1,
  'the partner can still attach a document to a shared flight'
);

-- Unfiltered, so the DELETE policy decides rather than the SELECT policy standing in front of it.
with d as (delete from public.flight_documents returning file_path)
select is((select count(*)::int from d), 2, 'an unfiltered delete removes only the two documents on the shared flight');

reset role;
select results_eq(
  $$select file_path from public.flight_documents order by file_path$$,
  $$values ('c/f/dual.pdf'::text), ('c/f/private.pdf')$$,
  'both documents on the private flight survive — the dual-parented one included'
);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- DELETE on flights. The creator's own private flight goes first, so it is out of the way before
-- the unfiltered statements below sweep up whatever is still visible.
-- ---------------------------------------------------------------------------
with d as (delete from public.flights where id = '55555555-4444-0000-0000-000000000055' returning 1)
select is((select count(*)::int from d), 1, 'the creator can still delete their own private flight');

with d as (delete from public.flights where id = '11111111-4444-0000-0000-000000000011' returning 1)
select is((select count(*)::int from d), 0, 'the partner cannot delete a private flight they did not create');

-- ---------------------------------------------------------------------------
-- The two exploits, in the only shape that reaches the UPDATE and DELETE policies at all.
-- ---------------------------------------------------------------------------

-- Before 20260916000000 this touched 2 rows and made Ann's private flight readable on the next
-- select. It has to succeed — the flights Ben can see are legitimately his to update — while
-- leaving the private one alone.
update public.flights set shared = true;

reset role;
select is(
  (select shared from public.flights where id = '11111111-4444-0000-0000-000000000011'),
  false,
  'an unfiltered "set shared = true" does not reach the private flight'
);
set local role authenticated;

-- Before 20260916000000 this destroyed the private flight outright.
delete from public.flights;

reset role;
select is(
  (select count(*)::int from public.flights where id = '11111111-4444-0000-0000-000000000011'),
  1,
  'the private flight survives an unfiltered "delete from flights"'
);
select is(
  (select count(*)::int from public.flights where id = '22222222-4444-0000-0000-000000000022'),
  0,
  'while the shared flight, which the partner could see, is gone — so the statement did run'
);
select is(
  (select count(*)::int from public.flight_updates where flight_id = '11111111-4444-0000-0000-000000000011'),
  1,
  'and the private flight''s updates were never cascaded away with it'
);

select * from finish();
rollback;
