-- The keys have to be captured before the cascade, and they have to be the right couple's.
--
-- Both halves are load-bearing and they fail in opposite directions. Capture too late and the rows
-- naming the objects are already gone, which is the bug this replaces: a purged couple's
-- photographs stay in R2 with nothing left to identify them. Capture too much and a purge deletes
-- somebody else's photographs, which is worse than the bug — so the assertion that couple B's keys
-- are absent is the one that matters most in this file.

begin;
select plan(12);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa1111-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a1@purge.test', 'x', now(), now()),
  ('aaaa1111-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a2@purge.test', 'x', now(), now()),
  ('bbbb2222-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b1@purge.test', 'x', now(), now()),
  ('bbbb2222-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b2@purge.test', 'x', now(), now())
on conflict do nothing;

insert into public.couples (id, partner_a_id, partner_b_id, status) values
  ('cccc0000-0000-4000-8000-00000000000a', 'aaaa1111-0000-4000-8000-000000000001', 'aaaa1111-0000-4000-8000-000000000002', 'active'),
  ('cccc0000-0000-4000-8000-00000000000b', 'bbbb2222-0000-4000-8000-000000000001', 'bbbb2222-0000-4000-8000-000000000002', 'active');

insert into public.places (id, city, country, latitude, longitude)
values ('9999aaaa-0000-4000-8000-000000000001', 'Purgeville', 'Testland', -33.86, 151.2);

-- Couple A: two memory photos, a flight-parented document, and a trip-parented one.
insert into public.memories (id, couple_id, title) values
  ('deed0000-0000-4000-8000-00000000000a', 'cccc0000-0000-4000-8000-00000000000a', 'Ours');
insert into public.memory_photos (memory_id, photo_path, position) values
  ('deed0000-0000-4000-8000-00000000000a', 'cccc0000-0000-4000-8000-00000000000a/deed0000-0000-4000-8000-00000000000a/p1.jpg', 0),
  ('deed0000-0000-4000-8000-00000000000a', 'cccc0000-0000-4000-8000-00000000000a/deed0000-0000-4000-8000-00000000000a/p2.jpg', 1);

insert into public.flights (id, couple_id) values
  ('f11f0000-0000-4000-8000-00000000000a', 'cccc0000-0000-4000-8000-00000000000a');
insert into public.trips (id, couple_id, origin_id, destination_id, departure_at, arrival_at, category)
values ('7211f000-0000-4000-8000-00000000000a', 'cccc0000-0000-4000-8000-00000000000a',
        '9999aaaa-0000-4000-8000-000000000001', '9999aaaa-0000-4000-8000-000000000001',
        now(), now() + interval '1 day', 'seeing_each_other');

insert into public.flight_documents (flight_id, uploaded_by, file_path) values
  ('f11f0000-0000-4000-8000-00000000000a', 'aaaa1111-0000-4000-8000-000000000001',
   'cccc0000-0000-4000-8000-00000000000a/f11f0000-0000-4000-8000-00000000000a/boarding.pdf');
-- Parented by a trip rather than a flight. `flight_documents` carries both columns and the privacy
-- tests exercise a dual-parent row, so a collector that only followed `flight_id` would strand this.
insert into public.flight_documents (trip_id, uploaded_by, file_path) values
  ('7211f000-0000-4000-8000-00000000000a', 'aaaa1111-0000-4000-8000-000000000001',
   'cccc0000-0000-4000-8000-00000000000a/7211f000-0000-4000-8000-00000000000a/itinerary.pdf');

-- Couple B: the control. Nothing below should touch any of this.
insert into public.memories (id, couple_id, title) values
  ('deed0000-0000-4000-8000-00000000000b', 'cccc0000-0000-4000-8000-00000000000b', 'Theirs');
insert into public.memory_photos (memory_id, photo_path, position) values
  ('deed0000-0000-4000-8000-00000000000b', 'cccc0000-0000-4000-8000-00000000000b/deed0000-0000-4000-8000-00000000000b/p1.jpg', 0);
insert into public.flights (id, couple_id) values
  ('f11f0000-0000-4000-8000-00000000000b', 'cccc0000-0000-4000-8000-00000000000b');
insert into public.flight_documents (flight_id, uploaded_by, file_path) values
  ('f11f0000-0000-4000-8000-00000000000b', 'bbbb2222-0000-4000-8000-000000000001',
   'cccc0000-0000-4000-8000-00000000000b/f11f0000-0000-4000-8000-00000000000b/theirs.pdf');

-- ---------------------------------------------------------------------------
-- The collector, before anything is destroyed
-- ---------------------------------------------------------------------------

select set_eq(
  $$select private.couple_object_keys('cccc0000-0000-4000-8000-00000000000a')$$,
  $$values
      ('memory-photos/cccc0000-0000-4000-8000-00000000000a/deed0000-0000-4000-8000-00000000000a/p1.jpg'),
      ('memory-photos/cccc0000-0000-4000-8000-00000000000a/deed0000-0000-4000-8000-00000000000a/p2.jpg'),
      ('flight-documents/cccc0000-0000-4000-8000-00000000000a/f11f0000-0000-4000-8000-00000000000a/boarding.pdf'),
      ('flight-documents/cccc0000-0000-4000-8000-00000000000a/7211f000-0000-4000-8000-00000000000a/itinerary.pdf'),
      ('drawing-pads/cccc0000-0000-4000-8000-00000000000a/aaaa1111-0000-4000-8000-000000000001/pad.png'),
      ('drawing-pads/cccc0000-0000-4000-8000-00000000000a/aaaa1111-0000-4000-8000-000000000002/pad.png')$$,
  'every object the couple owns, with its bucket prefix, and nothing else'
);

-- ---------------------------------------------------------------------------
-- The purge
-- ---------------------------------------------------------------------------

select public.purge_couple_data('cccc0000-0000-4000-8000-00000000000a');

select is(
  (select count(*)::int from public.pending_object_deletions),
  6,
  'the purge enqueued all six, and did so before the cascade removed the rows naming them'
);

select is(
  (select count(*)::int from public.memory_photos
   where memory_id = 'deed0000-0000-4000-8000-00000000000a'),
  0,
  'and the rows really are gone, so the enqueue could not have happened afterwards'
);

select ok(
  exists(select 1 from public.pending_object_deletions
         where key = 'memory-photos/cccc0000-0000-4000-8000-00000000000a/deed0000-0000-4000-8000-00000000000a/p1.jpg'),
  'a memory photo is queued under its bucket prefix'
);

select ok(
  exists(select 1 from public.pending_object_deletions
         where key = 'flight-documents/cccc0000-0000-4000-8000-00000000000a/7211f000-0000-4000-8000-00000000000a/itinerary.pdf'),
  'so is a document parented by a trip rather than a flight'
);

select ok(
  exists(select 1 from public.pending_object_deletions
         where key = 'drawing-pads/cccc0000-0000-4000-8000-00000000000a/aaaa1111-0000-4000-8000-000000000002/pad.png'),
  'and both partners'' drawing pads, whose paths exist in no column'
);

-- The assertion this file exists for.
select is(
  (select count(*)::int from public.pending_object_deletions where key like '%' || 'cccc0000-0000-4000-8000-00000000000b' || '%'),
  0,
  'nothing belonging to the other couple was queued for deletion'
);

select is(
  (select count(*)::int from public.memory_photos
   where memory_id = 'deed0000-0000-4000-8000-00000000000b'),
  1,
  'and the other couple still has their photo row'
);

-- ---------------------------------------------------------------------------
-- Idempotence: a retried deletion must not double-queue
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select public.purge_couple_data('cccc0000-0000-4000-8000-00000000000a')$$,
  'purging an already-purged couple is safe, because delete-account is documented as retryable'
);

select is(
  (select count(*)::int from public.pending_object_deletions),
  6,
  'and enqueues nothing new'
);

-- ---------------------------------------------------------------------------
-- scrub_account captures the avatar paths before it nulls them
-- ---------------------------------------------------------------------------

update public.profiles
set avatar_path = 'bbbb2222-0000-4000-8000-000000000001/avatar.jpg',
    partner_avatar_path = 'bbbb2222-0000-4000-8000-000000000001/partner-avatar.jpg'
where id = 'bbbb2222-0000-4000-8000-000000000001';

select private.scrub_account('bbbb2222-0000-4000-8000-000000000001');

select ok(
  exists(select 1 from public.pending_object_deletions
         where key = 'avatars/bbbb2222-0000-4000-8000-000000000001/avatar.jpg')
  and exists(select 1 from public.pending_object_deletions
         where key = 'avatars/bbbb2222-0000-4000-8000-000000000001/partner-avatar.jpg'),
  'both avatar keys are queued, though the scrub nulls the columns holding them in the same call'
);

select is(
  (select avatar_path from public.profiles where id = 'bbbb2222-0000-4000-8000-000000000001'),
  null,
  'and the column really was nulled, so the capture had to come first'
);

select * from finish();
rollback;
