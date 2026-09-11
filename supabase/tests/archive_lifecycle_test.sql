-- Unpairing archives; 90 days later it is gone; re-pairing inside the window can bring it back.
--
-- The assertions worth having are the boundaries: the day before the deadline nothing happens, the
-- day after everything does, and re-pairing — by either route — does not hand a couple a fresh set
-- of flights for the month.

begin;
select plan(22);

create extension if not exists pgtap;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-5555-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@life.test', 'x', now(), now()),
  ('aaaaaaaa-5555-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@life.test', 'x', now(), now())
on conflict do nothing;

insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('cccccccc-5555-0000-0000-00000000000c',
        'aaaaaaaa-5555-0000-0000-00000000000a',
        'aaaaaaaa-5555-0000-0000-00000000000b',
        'active');

insert into public.flights (id, couple_id, cancelled, diverted, status, tracking_enabled, shared,
                            pre_departure_notified, traveler_ids, arrival_1h_notified, arrival_30m_notified)
values ('11111111-5555-0000-0000-000000000001', 'cccccccc-5555-0000-0000-00000000000c',
        false, false, 'scheduled', false, true, false, '{}', false, false);

-- ---------------------------------------------------------------------------
-- An active couple has no expiry
-- ---------------------------------------------------------------------------

select is(
  (select scheduled_purge_at from public.couples where id = 'cccccccc-5555-0000-0000-00000000000c'),
  null::timestamptz, 'a live relationship is not an archive and has no deadline'
);

-- ---------------------------------------------------------------------------
-- Unpairing archives and starts the clock
-- ---------------------------------------------------------------------------

update public.couples
set status = 'dissolved', dissolved_at = now(), dissolved_by = 'aaaaaaaa-5555-0000-0000-00000000000a'
where id = 'cccccccc-5555-0000-0000-00000000000c';

-- The thing this whole design exists to protect: unpairing destroys nothing.
select is(
  (select count(*)::integer from public.flights where couple_id = 'cccccccc-5555-0000-0000-00000000000c'),
  1, 'unpairing does not delete the shared data'
);

select ok(
  (select scheduled_purge_at from public.couples where id = 'cccccccc-5555-0000-0000-00000000000c') is not null,
  'but it does start the clock'
);

select is(
  (select date_trunc('day', scheduled_purge_at - dissolved_at) from public.couples
   where id = 'cccccccc-5555-0000-0000-00000000000c'),
  interval '90 days', 'ninety days, measured from when it ended'
);

-- ---------------------------------------------------------------------------
-- The deadline itself
-- ---------------------------------------------------------------------------

-- One day short. Nothing may happen yet.
update public.couples set scheduled_purge_at = now() + interval '1 day'
where id = 'cccccccc-5555-0000-0000-00000000000c';

select is(private.purge_expired_couple_archives(), 0, 'nothing is deleted before the deadline');
select is(
  (select count(*)::integer from public.flights where couple_id = 'cccccccc-5555-0000-0000-00000000000c'),
  1, 'and the data is still there'
);

-- An active couple must never be swept up, whatever its stamp says.
--
-- Built in two statements on purpose. Doing it in one — `set status = 'active',
-- scheduled_purge_at = <past>` — does not test anything: trg_couples_archive_clock sees the
-- transition into 'active' and nulls the stamp, so the row ends up active with no deadline and the
-- purge job passes it over for the wrong reason. It did exactly that here, and the negative control
-- caught it: removing the status filter from the purge job broke nothing.
--
-- The trigger only fires on a status *change*, so stamping an already-active row is what actually
-- produces the state this guards against — a live couple carrying an expired deadline, which is
-- what a stray UPDATE or a future bug would leave behind.
update public.couples set status = 'active' where id = 'cccccccc-5555-0000-0000-00000000000c';
update public.couples set scheduled_purge_at = now() - interval '1 day'
where id = 'cccccccc-5555-0000-0000-00000000000c';

select ok(
  (select scheduled_purge_at from public.couples where id = 'cccccccc-5555-0000-0000-00000000000c') < now(),
  'the dangerous state is real: an active couple carrying an expired deadline'
);
select is(private.purge_expired_couple_archives(), 0, 'a live couple is never purged, past deadline or not');
select is(
  (select count(*)::integer from public.flights where couple_id = 'cccccccc-5555-0000-0000-00000000000c'),
  1, 'and its data is untouched'
);

update public.couples
set status = 'dissolved', dissolved_at = now() - interval '91 days'
where id = 'cccccccc-5555-0000-0000-00000000000c';
update public.couples set scheduled_purge_at = now() - interval '1 day'
where id = 'cccccccc-5555-0000-0000-00000000000c';

select is(private.purge_expired_couple_archives(), 1, 'past the deadline it goes');
select is(
  (select count(*)::integer from public.couples where id = 'cccccccc-5555-0000-0000-00000000000c'),
  0, 'and the shared data with it'
);
select is(
  (select count(*)::integer from public.flights where couple_id = 'cccccccc-5555-0000-0000-00000000000c'),
  0, 'including the flights'
);

-- ---------------------------------------------------------------------------
-- Re-pairing inside the window
-- ---------------------------------------------------------------------------

insert into public.couples (id, partner_a_id, partner_b_id, status, dissolved_at, scheduled_purge_at)
values ('cccccccc-5555-0000-0000-00000000000d',
        'aaaaaaaa-5555-0000-0000-00000000000a',
        'aaaaaaaa-5555-0000-0000-00000000000b',
        'dissolved', now() - interval '10 days', now() + interval '80 days');

insert into public.flights (id, couple_id, cancelled, diverted, status, tracking_enabled, shared,
                            pre_departure_notified, traveler_ids, arrival_1h_notified, arrival_30m_notified)
values ('11111111-5555-0000-0000-000000000002', 'cccccccc-5555-0000-0000-00000000000d',
        false, false, 'scheduled', false, true, false, '{}', false, false);

-- Flights tracked before the breakup, this calendar month.
insert into public.flight_additions (couple_id, flight_id, added_by, added_at)
select 'cccccccc-5555-0000-0000-00000000000d', null, 'aaaaaaaa-5555-0000-0000-00000000000a',
       greatest(date_trunc('month', now() at time zone 'utc'), now() - interval '9 days')
from generate_series(1, 4);

select is(public.flights_used_this_month('cccccccc-5555-0000-0000-00000000000d'), 4,
  'the archive still remembers the flights it spent');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-5555-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select couple_id from public.restorable_archive_with('aaaaaaaa-5555-0000-0000-00000000000b')),
  'cccccccc-5555-0000-0000-00000000000d'::uuid,
  'the archive is offered back while it is still inside its window'
);

reset role;

-- Restore it the way `respond_to_connection_request` does.
update public.couples
set status = 'active', dissolved_at = null, dissolved_by = null
where id = 'cccccccc-5555-0000-0000-00000000000d';

select is(
  (select scheduled_purge_at from public.couples where id = 'cccccccc-5555-0000-0000-00000000000d'),
  null::timestamptz, 'restoring cancels the deletion'
);

select is(
  (select count(*)::integer from public.flights where couple_id = 'cccccccc-5555-0000-0000-00000000000d'),
  1, 'and the shared data is simply live again — same couple, same ids, nothing moved'
);

-- ---------------------------------------------------------------------------
-- Re-pairing is not a way to reset the monthly flight limit
-- ---------------------------------------------------------------------------
--
-- The loophole this closes: a couple at 5 of 5 unpairs, re-pairs, and has five more. It was open
-- on both paths — restoring moved the counting window forward, and starting fresh minted a new
-- couples row with an empty ledger. Counting against the two people rather than the couple row
-- shuts both.
select is(public.flights_used_this_month('cccccccc-5555-0000-0000-00000000000d'), 4,
  'a restored couple keeps the flights it already spent this month');

select is(
  (select count(*)::integer from public.flight_additions where couple_id = 'cccccccc-5555-0000-0000-00000000000d'),
  4, 'the ledger itself is untouched'
);

-- The other half, and the one a couple_id-keyed count gets wrong: a brand new couples row for the
-- same two people. This is what "start fresh" would have produced.
insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('cccccccc-5555-0000-0000-00000000000e',
        'aaaaaaaa-5555-0000-0000-00000000000b',
        'aaaaaaaa-5555-0000-0000-00000000000a',
        'dissolved');
-- Pushed past its deadline so it is not a second restorable archive competing with the assertion
-- at the end of this file. Done as a separate UPDATE because the insert trigger stamps it.
update public.couples set scheduled_purge_at = now() - interval '1 day'
where id = 'cccccccc-5555-0000-0000-00000000000e';

select is(public.flights_used_this_month('cccccccc-5555-0000-0000-00000000000e'), 4,
  'and a brand new couple row for the same two people inherits the month too');

-- Someone else entirely is unaffected — this counts the couple's own two people, not everyone.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values ('aaaaaaaa-5555-0000-0000-00000000000f', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cal@life.test', 'x', now(), now())
on conflict do nothing;

insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('cccccccc-5555-0000-0000-00000000000f',
        'aaaaaaaa-5555-0000-0000-00000000000f',
        'aaaaaaaa-5555-0000-0000-00000000000b',
        'dissolved');
update public.couples set scheduled_purge_at = now() - interval '1 day'
where id = 'cccccccc-5555-0000-0000-00000000000f';

select is(public.flights_used_this_month('cccccccc-5555-0000-0000-00000000000f'), 0,
  'a couple sharing neither of those two people starts at zero');

-- ---------------------------------------------------------------------------
-- A dissolved couple always has a deadline
-- ---------------------------------------------------------------------------
--
-- Inserted straight in as dissolved, which the UPDATE-only version of the trigger missed. Such a
-- row is immortal: the purge job skips a null stamp, so it is never deleted, and it stays
-- restorable forever.
insert into public.couples (id, partner_a_id, partner_b_id, status, dissolved_at)
values ('cccccccc-5555-0000-0000-0000000000aa',
        'aaaaaaaa-5555-0000-0000-00000000000f',
        'aaaaaaaa-5555-0000-0000-00000000000a',
        'dissolved', now() - interval '5 days');

select ok(
  (select scheduled_purge_at from public.couples where id = 'cccccccc-5555-0000-0000-0000000000aa') is not null,
  'a couple inserted as dissolved gets a deadline too, not an immortal archive'
);

-- ---------------------------------------------------------------------------
-- An archive past its deadline is not offered back
-- ---------------------------------------------------------------------------

update public.couples
set status = 'dissolved', dissolved_at = now() - interval '100 days', scheduled_purge_at = now() - interval '10 days'
where id = 'cccccccc-5555-0000-0000-00000000000d';

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-5555-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select count(*)::integer from public.restorable_archive_with('aaaaaaaa-5555-0000-0000-00000000000b')),
  0, 'an archive past its deadline is never offered — re-pairing then starts fresh'
);

reset role;
select * from finish();
rollback;
