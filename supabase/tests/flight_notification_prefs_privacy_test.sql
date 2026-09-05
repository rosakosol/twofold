-- ---------------------------------------------------------------------------
-- flight_notification_preferences: a pref row cannot be repointed at a hidden flight
-- ---------------------------------------------------------------------------
--
-- The last of the flight-privacy sweep, and the assertions here are shaped by an awkward fact:
-- the repoint this migration forbids is ALREADY refused without it, by the SELECT policy. Postgres
-- requires an updated row to stay visible under SELECT, and that policy has carried the flight
-- check since 20260712110000.
--
-- So a plain "the repoint is refused" test passes with or without the migration and proves nothing
-- about it — the first version of this file did exactly that. Test 5 is the one that discriminates:
-- it relaxes the SELECT policy inside the transaction, removing the incidental protection, and
-- asserts the UPDATE policy refuses the write on its own. That is the property being added, and it
-- fails without the migration.
--
-- Fixtures mirror `flight_privacy_test.sql`: Ann and Ben are a couple, Ann owns a private flight
-- and a shared one.

begin;
select plan(6);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-5555-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@prefsprivacy.test', 'x', now(), now(), now()),
  ('bbbbbbbb-5555-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@prefsprivacy.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name) values
  ('aaaaaaaa-5555-0000-0000-000000000001', 'Ann'),
  ('bbbbbbbb-5555-0000-0000-000000000002', 'Ben')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('cccccccc-5555-0000-0000-000000000003',
        'aaaaaaaa-5555-0000-0000-000000000001',
        'bbbbbbbb-5555-0000-0000-000000000002',
        'active');

--   ...11  Ann's PRIVATE flight — Ben must not be able to point a pref row at it
--   ...22  Ann's SHARED flight  — the control
insert into public.flights (id, couple_id, created_by, shared, flight_number_iata)
values
  ('11111111-5555-0000-0000-000000000011', 'cccccccc-5555-0000-0000-000000000003',
   'aaaaaaaa-5555-0000-0000-000000000001', false, 'QF31'),
  ('22222222-5555-0000-0000-000000000022', 'cccccccc-5555-0000-0000-000000000003',
   'aaaaaaaa-5555-0000-0000-000000000001', true, 'QF32');

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-5555-0000-0000-000000000002","role":"authenticated"}';

-- Ben legitimately sets a preference on the shared flight. This must keep working — the fix is
-- worthless if it breaks the ordinary path.
select lives_ok(
  $$insert into public.flight_notification_preferences (flight_id, profile_id)
    values ('22222222-5555-0000-0000-000000000022', 'bbbbbbbb-5555-0000-0000-000000000002')$$,
  'a preference on a shared flight still inserts'
);

-- INSERT already carried the flight check before this migration (20260712110000), so this is a
-- regression guard rather than the fix.
select throws_ok(
  $$insert into public.flight_notification_preferences (flight_id, profile_id)
    values ('11111111-5555-0000-0000-000000000011', 'bbbbbbbb-5555-0000-0000-000000000002')$$,
  '42501',
  null,
  'a preference cannot be created against a flight Ben cannot see'
);

-- The actual gap: repointing an existing, legitimately-owned row at the private flight.
select throws_ok(
  $$update public.flight_notification_preferences
      set flight_id = '11111111-5555-0000-0000-000000000011'
    where profile_id = 'bbbbbbbb-5555-0000-0000-000000000002'$$,
  '42501',
  null,
  'an existing preference cannot be repointed at a flight Ben cannot see'
);

select is(
  (select flight_id from public.flight_notification_preferences
    where profile_id = 'bbbbbbbb-5555-0000-0000-000000000002'),
  '22222222-5555-0000-0000-000000000022'::uuid,
  'and the row still names the flight it was created for'
);

-- Ordinary edits to a row on a flight Ben CAN see are untouched. `using` still only requires
-- ownership, so this is the assertion that proves the new `with check` did not over-tighten.
select lives_ok(
  $$update public.flight_notification_preferences
      set profile_id = 'bbbbbbbb-5555-0000-0000-000000000002'
    where flight_id = '22222222-5555-0000-0000-000000000022'$$,
  'a preference on a visible flight is still editable'
);

-- The discriminating test. With SELECT relaxed the incidental protection is gone, so anything
-- refusing the write now is the UPDATE policy's own `with check` — the thing this migration adds.
--
-- `reset role` first: policy DDL needs the table owner, and `authenticated` cannot drop one. Left
-- as `authenticated` this aborts the transaction and pgTAP reports "planned 6 but ran 5".
reset role;
drop policy "flight_notification_preferences_select_members" on public.flight_notification_preferences;
create policy "tmp_select_all" on public.flight_notification_preferences for select using (true);

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-5555-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$update public.flight_notification_preferences
      set flight_id = '11111111-5555-0000-0000-000000000011'
    where profile_id = 'bbbbbbbb-5555-0000-0000-000000000002'$$,
  '42501',
  null,
  'the UPDATE policy refuses the repoint on its own, without the SELECT policy covering for it'
);

select * from finish();
rollback;
