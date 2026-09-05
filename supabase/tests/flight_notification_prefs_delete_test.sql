-- ---------------------------------------------------------------------------
-- flight_notification_preferences: deleting your own preference
-- ---------------------------------------------------------------------------
--
-- The table had no delete policy at all until 20260925000000. Two properties here, and the second
-- is a limitation rather than a guarantee — recorded on purpose, because it is the opposite of what
-- adding a delete policy looks like it should achieve.

begin;
select plan(5);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-1414-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@prefsdel.test', 'x', now(), now(), now()),
  ('bbbbbbbb-1414-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@prefsdel.test', 'x', now(), now(), now());

insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('cccccccc-1414-0000-0000-000000000003',
        'aaaaaaaa-1414-0000-0000-000000000001',
        'bbbbbbbb-1414-0000-0000-000000000002',
        'active');

-- Two of Ann's flights, both shared to begin with. ...22 stays shared; ...11 gets un-shared later.
insert into public.flights (id, couple_id, created_by, shared, flight_number_iata)
values
  ('11111111-1414-0000-0000-000000000011', 'cccccccc-1414-0000-0000-000000000003',
   'aaaaaaaa-1414-0000-0000-000000000001', true, 'QF31'),
  ('22222222-1414-0000-0000-000000000022', 'cccccccc-1414-0000-0000-000000000003',
   'aaaaaaaa-1414-0000-0000-000000000001', true, 'QF32');

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-1414-0000-0000-000000000002","role":"authenticated"}';

insert into public.flight_notification_preferences (flight_id, profile_id) values
  ('11111111-1414-0000-0000-000000000011', 'bbbbbbbb-1414-0000-0000-000000000002'),
  ('22222222-1414-0000-0000-000000000022', 'bbbbbbbb-1414-0000-0000-000000000002');

-- ---------------------------------------------------------------------------
-- The capability being added
-- ---------------------------------------------------------------------------

delete from public.flight_notification_preferences
  where flight_id = '22222222-1414-0000-0000-000000000022';

select is(
  (select count(*)::int from public.flight_notification_preferences
    where flight_id = '22222222-1414-0000-0000-000000000022'),
  0,
  'you can delete your own preference on a flight you can see'
);

-- Ann must not be able to delete Ben's. `using (profile_id = auth.uid())` filters rather than
-- raises, so this asserts the row survives rather than expecting an error.
set local request.jwt.claims = '{"sub":"aaaaaaaa-1414-0000-0000-000000000001","role":"authenticated"}';
delete from public.flight_notification_preferences
  where profile_id = 'bbbbbbbb-1414-0000-0000-000000000002';

reset role;
select is(
  (select count(*)::int from public.flight_notification_preferences
    where profile_id = 'bbbbbbbb-1414-0000-0000-000000000002'),
  1,
  'the partner cannot delete a preference belonging to someone else'
);

-- ---------------------------------------------------------------------------
-- The limitation, pinned so it is not rediscovered
-- ---------------------------------------------------------------------------
--
-- Adding a delete policy looks like it should let someone clear up a row for a flight that has
-- since been hidden from them. It does not: a DELETE has to locate its rows, and the SELECT policy
-- carries the flight check, so the row is filtered out before the delete policy is consulted.
-- Relieving this needs the SELECT policy to admit your own row regardless of the flight, which is a
-- widening of a read policy and a separate decision.

update public.flights set shared = false where id = '11111111-1414-0000-0000-000000000011';

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-1414-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select count(*)::int from public.flight_notification_preferences
    where flight_id = '11111111-1414-0000-0000-000000000011'),
  0,
  'once the flight is hidden, the owner can no longer see their own preference'
);

delete from public.flight_notification_preferences
  where flight_id = '11111111-1414-0000-0000-000000000011';

reset role;
select is(
  (select count(*)::int from public.flight_notification_preferences
    where flight_id = '11111111-1414-0000-0000-000000000011'),
  1,
  'and cannot delete it either — the row survives, which is the stranding this does NOT fix'
);

-- Once the flight is visible again, so is the row, and it can be cleared up.
update public.flights set shared = true where id = '11111111-1414-0000-0000-000000000011';

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-1414-0000-0000-000000000002","role":"authenticated"}';
delete from public.flight_notification_preferences
  where flight_id = '11111111-1414-0000-0000-000000000011';

reset role;
select is(
  (select count(*)::int from public.flight_notification_preferences
    where flight_id = '11111111-1414-0000-0000-000000000011'),
  0,
  'sharing it again makes the row reachable and deletable, so the stranding is recoverable'
);

select * from finish();
rollback;
