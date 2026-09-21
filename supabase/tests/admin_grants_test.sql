-- Grants and overrides are the non-destructive half of the console, which is exactly why they are
-- worth testing: nothing here fails loudly when it goes wrong.
--
--   * A grant that skipped its authorisation check hands out paid features, and the only symptom
--     is revenue that never arrives.
--   * A flight-limit override decides how much AeroAPI money an account may spend. Its own table
--     lives in `private` specifically so no client can write itself an unlimited bill, and these
--     functions are the first thing ever to write it from outside a SQL prompt.
--   * A credit granted without a reason is a credit nobody can explain later. The table's own
--     comment makes the point about overrides: "an unexplained override found in two years' time
--     is indistinguishable from a mistake, and nobody will dare delete it."
--
-- And one thing that is not about authorisation: an admin grant has to be distinguishable from a
-- purchase. `transaction_id` is the store transaction, and a comped credit that looked like a
-- bought one would quietly corrupt any later attempt to reconcile credits against payments.

begin;
select plan(16);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, 'x', now(), now(), now()
from (values
  ('11111111-bbbb-0000-0000-000000000001'::uuid, 'support@grants.test'),
  ('11111111-bbbb-0000-0000-000000000002'::uuid, 'content@grants.test'),
  ('11111111-bbbb-0000-0000-000000000003'::uuid, 'subject@grants.test'),
  ('11111111-bbbb-0000-0000-000000000004'::uuid, 'pest@grants.test'),
  ('11111111-bbbb-0000-0000-000000000005'::uuid, 'a@grants.test'),
  ('11111111-bbbb-0000-0000-000000000006'::uuid, 'b@grants.test')
) as v(id, email);

insert into public.profiles (id, first_name) values
  ('11111111-bbbb-0000-0000-000000000001', 'Sam'),
  ('11111111-bbbb-0000-0000-000000000002', 'Con'),
  ('11111111-bbbb-0000-0000-000000000003', 'Kit'),
  ('11111111-bbbb-0000-0000-000000000004', 'Pest'),
  ('11111111-bbbb-0000-0000-000000000005', 'Ann'),
  ('11111111-bbbb-0000-0000-000000000006', 'Ben')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.feedback_admins (profile_id, role) values
  ('11111111-bbbb-0000-0000-000000000001', 'support'),
  ('11111111-bbbb-0000-0000-000000000002', 'content');

-- Two unrelated people have blocked the same account. One block is a falling-out; two is a signal.
insert into public.blocked_profiles (blocker_id, blocked_id) values
  ('11111111-bbbb-0000-0000-000000000005', '11111111-bbbb-0000-0000-000000000004'),
  ('11111111-bbbb-0000-0000-000000000006', '11111111-bbbb-0000-0000-000000000004'),
  ('11111111-bbbb-0000-0000-000000000005', '11111111-bbbb-0000-0000-000000000006');

set local role authenticated;

-- ---------------------------------------------------------------------------
-- Not a support admin
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '11111111-bbbb-0000-0000-000000000002', true);

select throws_ok(
  $$ select public.admin_grant_streak_repair('11111111-bbbb-0000-0000-000000000003', 'because') $$,
  '42501', null, 'a content admin cannot hand out streak repairs'
);

select throws_ok(
  $$ select public.admin_set_flight_limit('11111111-bbbb-0000-0000-000000000003', 999, 'because') $$,
  '42501', null, 'nor raise what an account may spend at AeroAPI'
);

select throws_ok(
  $$ select * from public.admin_most_blocked() $$,
  '42501', null, 'nor see who is being blocked'
);

-- ---------------------------------------------------------------------------
-- A reason is not optional
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '11111111-bbbb-0000-0000-000000000001', true);

select throws_ok(
  $$ select public.admin_grant_streak_repair('11111111-bbbb-0000-0000-000000000003', '  ') $$,
  '22023', null, 'a grant needs a reason'
);

select throws_ok(
  $$ select public.admin_set_flight_limit('11111111-bbbb-0000-0000-000000000003', 999, '') $$,
  '22023', null, 'and so does an override'
);

select throws_ok(
  $$ select public.admin_set_flight_limit('11111111-bbbb-0000-0000-000000000003', -1, 'oops') $$,
  '22023', null, 'a negative limit is refused before it reaches the check constraint'
);

select throws_ok(
  $$ select public.admin_grant_record_export('00000000-0000-0000-0000-0000000000ff', 'ghost') $$,
  'P0001', 'no such account', 'and an account that does not exist is refused by name'
);

-- ---------------------------------------------------------------------------
-- Granting
-- ---------------------------------------------------------------------------

select lives_ok(
  $$ select public.admin_grant_streak_repair('11111111-bbbb-0000-0000-000000000003', 'streak lost to our own outage') $$,
  'a support admin can grant a streak repair'
);

select lives_ok(
  $$ select public.admin_grant_record_export('11111111-bbbb-0000-0000-000000000003', 'export failed twice, gave them another') $$,
  'and a record export'
);

-- Twice, because a support admin will be asked twice and a unique-constraint collision on a
-- synthetic id would be a self-inflicted failure.
select lives_ok(
  $$ select public.admin_grant_streak_repair('11111111-bbbb-0000-0000-000000000003', 'and again') $$,
  'granting the same thing twice does not collide on the synthetic transaction id'
);

reset role;

select is(
  (select count(*)::integer from public.streak_repair_credits
   where profile_id = '11111111-bbbb-0000-0000-000000000003' and consumed_at is null),
  2, 'both credits are there and unconsumed'
);

-- The reconciliation property: a comped credit is visibly not a purchase.
select ok(
  (select bool_and(transaction_id like 'admin:%') from public.streak_repair_credits
   where profile_id = '11111111-bbbb-0000-0000-000000000003'),
  'and each is marked as an admin grant rather than looking like a purchase'
);

-- ---------------------------------------------------------------------------
-- Overrides, set and removed
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-bbbb-0000-0000-000000000001', true);

select public.admin_set_flight_limit('11111111-bbbb-0000-0000-000000000003', 500, 'testing an airline integration');

select is(
  public.admin_flight_limit_override('11111111-bbbb-0000-0000-000000000003') #>> '{monthly_limit}',
  '500', 'the override is set'
);

-- The reason lands in the table's own note column as well as the audit log, because somebody
-- reading `private.flight_limit_overrides` directly in two years will not have the log open.
select is(
  public.admin_flight_limit_override('11111111-bbbb-0000-0000-000000000003') #>> '{note}',
  'testing an airline integration', 'and carries its reason in the row itself'
);

select public.admin_set_flight_limit('11111111-bbbb-0000-0000-000000000003', null, 'integration finished');

select ok(
  public.admin_flight_limit_override('11111111-bbbb-0000-0000-000000000003') is null,
  'a null limit removes it, so support can put an account back to normal'
);

-- ---------------------------------------------------------------------------
-- Who is being blocked
-- ---------------------------------------------------------------------------

-- Ranked, with a floor, so one falling-out does not appear as a safety signal. Ben was blocked
-- once and must not be in the list; Pest was blocked by two unrelated people and must be.
select results_eq(
  $$ select profile_id, blocked_by_count from public.admin_most_blocked(2, 50) $$,
  $$ values ('11111111-bbbb-0000-0000-000000000004'::uuid, 2::bigint) $$,
  'only accounts blocked by more than one person are surfaced'
);

reset role;
select * from finish();
rollback;
