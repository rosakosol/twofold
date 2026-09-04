-- `live_activity_push_tokens` is a registration to be *pushed* a flight's live state, so writing a
-- row is a read grant in disguise. Its original policy (20260712030000) tested `profile_id =
-- auth.uid()` and nothing else, which made the row's `flight_id` entirely the caller's choice.
--
-- The Edge Function path was never the problem: `register-live-activity-token` 403s on a flight the
-- caller's own RLS-scoped select can't return. What the policy permitted was a direct PostgREST
-- insert naming a private flight's UUID, which meets no other gate. 20260917000000 closes that on
-- INSERT and on UPDATE's WITH CHECK.
--
-- The other half of that migration is what it deliberately does NOT do, and half the assertions
-- below exist to pin it. SELECT and DELETE still ask only for ownership, because a flight check
-- there would strand rows: Ben starts a Live Activity on a flight Ann has shared, Ann later
-- un-shares it, and Ben's perfectly legitimate token row now names a flight he can't see. If the
-- policies hid or protected that row, `end-live-activity-token` (which deletes by activity_id +
-- profile_id, having no flight to consult) would silently match nothing and the Activity on his
-- Lock Screen could never be torn down. Refusing to push to that row is `notifyLiveActivity`'s job,
-- under the service role, where dropping a token doesn't cost its owner the ability to delete it.
--
-- So the shape of this file is: the leak is closed on the two commands that create the grant, and
-- provably still open on the two commands that clean it up.

begin;
select plan(11);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-5555-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@latokens.test', 'x', now(), now(), now()),
  ('bbbbbbbb-5555-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@latokens.test', 'x', now(), now(), now());

-- A trigger on auth.users already created these rows, so this fills in the fields the
-- tests care about rather than inserting fresh.
insert into public.profiles (id, first_name) values
  ('aaaaaaaa-5555-0000-0000-000000000001', 'Ann'),
  ('bbbbbbbb-5555-0000-0000-000000000002', 'Ben')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.couples (id, partner_a_id, partner_b_id, status)
values ('cccccccc-5555-0000-0000-000000000003',
        'aaaaaaaa-5555-0000-0000-000000000001',
        'bbbbbbbb-5555-0000-0000-000000000002',
        'active');

-- Three flights, all Ann's, all in the one couple. No trip: nothing here reaches a couple through
-- `flights.trip_id`, and `can_see_flight` reads `couple_id` off the flight row directly.
--   ...11  PRIVATE       — the flight Ben must not be able to register a token against
--   ...22  SHARED        — the control: the normal case has to keep working
--   ...33  SHARED-FOR-NOW — Ben registers on it while it is shared, then Ann un-shares it. This is
--                          the row the anti-stranding assertions are about.
insert into public.flights (id, couple_id, created_by, shared, fa_flight_id)
values
  ('11111111-5555-0000-0000-000000000011', 'cccccccc-5555-0000-0000-000000000003', 'aaaaaaaa-5555-0000-0000-000000000001', false, 'ANN-PRIVATE'),
  ('22222222-5555-0000-0000-000000000022', 'cccccccc-5555-0000-0000-000000000003', 'aaaaaaaa-5555-0000-0000-000000000001', true,  'ANN-SHARED'),
  ('33333333-5555-0000-0000-000000000033', 'cccccccc-5555-0000-0000-000000000003', 'aaaaaaaa-5555-0000-0000-000000000001', true,  'ANN-SHARED-FOR-NOW');

-- ---------------------------------------------------------------------------
-- Ben, the partner. Every insert below is the direct-PostgREST shape — no Edge Function in front
-- of it, which is precisely the path that had nothing checking the flight.
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', 'bbbbbbbb-5555-0000-0000-000000000002', true);

-- The defect. Ben owns the row (profile_id is his own), so the old policy accepted it outright and
-- the server pushed him Ann's private flight's status, gates and actual times from then on. All he
-- needed was its UUID.
select throws_ok(
  $$insert into public.live_activity_push_tokens (flight_id, profile_id, activity_id, push_token)
    values ('11111111-5555-0000-0000-000000000011', 'bbbbbbbb-5555-0000-0000-000000000002', 'ben-on-private', 'deadbeef')$$,
  '42501',
  null,
  'the partner cannot register a Live Activity token for a private flight they did not create'
);

-- The control, and the reason the fix is `profile_id = auth.uid() and can_see_flight(...)` rather
-- than something blunter: a shared flight is exactly what both partners are meant to run their own
-- Activity on.
insert into public.live_activity_push_tokens (flight_id, profile_id, activity_id, push_token)
values ('22222222-5555-0000-0000-000000000022', 'bbbbbbbb-5555-0000-0000-000000000002', 'ben-on-shared', 'cafe01');
select is(
  (select count(*)::int from public.live_activity_push_tokens where activity_id = 'ben-on-shared'),
  1,
  'the partner can still register a token for a shared flight'
);

-- Registered while ...33 is still shared, so it is a legitimate row by every rule in force at the
-- moment it is written. Ann un-shares the flight further down.
insert into public.live_activity_push_tokens (flight_id, profile_id, activity_id, push_token)
values ('33333333-5555-0000-0000-000000000033', 'bbbbbbbb-5555-0000-0000-000000000002', 'ben-on-soon-private', 'cafe02');

-- UPDATE's WITH CHECK. Without it the INSERT rule is a formality: register on a flight you can see,
-- then repoint the row at one you cannot, and the grant is the same grant in two statements. USING
-- passes here (it is Ben's own row) — the refusal comes from the candidate row's flight.
select throws_ok(
  $$update public.live_activity_push_tokens
      set flight_id = '11111111-5555-0000-0000-000000000011'
      where activity_id = 'ben-on-shared'$$,
  '42501',
  null,
  'a token row cannot be repointed at a flight its owner cannot see'
);

select is(
  (select flight_id from public.live_activity_push_tokens where activity_id = 'ben-on-shared'),
  '22222222-5555-0000-0000-000000000022'::uuid,
  'and the row still names the flight it was registered for'
);

-- The update path that actually exists: ActivityKit hands over a fresh push token mid-Activity and
-- `register-live-activity-token` upserts on `activity_id`, whose DO UPDATE arm is this statement.
-- If the migration had put the flight check in USING as well, this would still pass today — but the
-- assertion is here because it is the everyday write, and a privacy fix that breaks it is a
-- regression however correct it looks.
with u as (
  update public.live_activity_push_tokens set push_token = 'cafe01-refreshed'
  where activity_id = 'ben-on-shared'
  returning 1
)
select is((select count(*)::int from u), 1, 'the owner can still refresh their own token''s push_token');

-- ---------------------------------------------------------------------------
-- Ann, the creator. Same private flight, opposite answer — the rule is about visibility, not about
-- which partner is asking.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'aaaaaaaa-5555-0000-0000-000000000001', true);

insert into public.live_activity_push_tokens (flight_id, profile_id, activity_id, push_token)
values ('11111111-5555-0000-0000-000000000011', 'aaaaaaaa-5555-0000-0000-000000000001', 'ann-on-private', 'beef01');
select is(
  (select count(*)::int from public.live_activity_push_tokens where activity_id = 'ann-on-private'),
  1,
  'the creator can register a token for their own private flight'
);

insert into public.live_activity_push_tokens (flight_id, profile_id, activity_id, push_token)
values ('22222222-5555-0000-0000-000000000022', 'aaaaaaaa-5555-0000-0000-000000000001', 'ann-on-shared', 'beef02');
select is(
  (select count(*)::int from public.live_activity_push_tokens where activity_id = 'ann-on-shared'),
  1,
  'and for a shared flight — both partners can run their own Activity on the same flight'
);

-- The un-share. Allowed: `flights_update_members` (20260916000000) lets a creator set
-- `shared = false` on their own flight, which is the entire point of the toggle. Ben's token row on
-- this flight is now a row naming a flight he cannot see.
update public.flights set shared = false where id = '33333333-5555-0000-0000-000000000033';

-- ---------------------------------------------------------------------------
-- Ben again. The anti-stranding property: his row survived a change he had no part in and no way to
-- anticipate, and he must not be locked out of it.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'bbbbbbbb-5555-0000-0000-000000000002', true);

select is(
  (select count(*)::int from public.flights where id = '33333333-5555-0000-0000-000000000033'),
  0,
  'the flight really has gone invisible to the partner — so the two assertions below are about a row whose flight they cannot see'
);

select is(
  (select count(*)::int from public.live_activity_push_tokens where activity_id = 'ben-on-soon-private'),
  1,
  'the owner can still SELECT their own token row after its flight became invisible to them'
);

-- Exactly `end-live-activity-token`'s statement: activity_id + profile_id, no flight anywhere in
-- it. A flight check on the DELETE policy would make this match zero rows and leave a Live Activity
-- on the Lock Screen that the client could never end.
with d as (
  delete from public.live_activity_push_tokens
  where activity_id = 'ben-on-soon-private' and profile_id = 'bbbbbbbb-5555-0000-0000-000000000002'
  returning 1
)
select is((select count(*)::int from d), 1, 'and can still DELETE it — the row is never stranded');

-- The asymmetry, from the other side: reading and deleting an existing row is always allowed,
-- creating a new one on that same now-invisible flight is not. Ben cannot re-register.
select throws_ok(
  $$insert into public.live_activity_push_tokens (flight_id, profile_id, activity_id, push_token)
    values ('33333333-5555-0000-0000-000000000033', 'bbbbbbbb-5555-0000-0000-000000000002', 'ben-again', 'cafe03')$$,
  '42501',
  null,
  'but cannot register a fresh token for that flight once it has gone private'
);

select * from finish();
rollback;
