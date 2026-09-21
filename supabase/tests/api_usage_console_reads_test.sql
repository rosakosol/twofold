-- These three functions are the only way into `private.api_usage_*`, and they are security
-- definer, which means the gate inside each body is the entire boundary. `private` being unserved
-- by PostgREST protects the tables; it protects nothing here, because these live in `public` and
-- PostgREST serves them to anyone with a session.
--
-- So the thing worth pinning is not that they return the right numbers — the rollup's own test
-- does that — but that they refuse the wrong caller. Three ways that goes wrong:
--
--   * A signed-in user with no role at all reads how much every couple flies. The usage tables
--     carry fa_flight_id and couple_id, and even the aggregates describe the shape of the
--     business.
--   * A content admin — somebody trusted to edit a trivia deck — reads the same. That is exactly
--     the separation 20261109000000 created the roles for, and it only exists if each function
--     checks the role it needs rather than merely "is an admin".
--   * `is_console_admin` is too narrow and locks a billing-only admin out of the console
--     altogether, which is how the role split ends up undone by the door in front of it.

begin;
select plan(13);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('dddddddd-8888-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'billing@usageconsole.test', 'x', now(), now(), now()),
  ('dddddddd-8888-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'content@usageconsole.test', 'x', now(), now(), now()),
  ('dddddddd-8888-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'nobody@usageconsole.test', 'x', now(), now(), now());

insert into public.profiles (id, first_name) values
  ('dddddddd-8888-0000-0000-000000000001', 'Bill'),
  ('dddddddd-8888-0000-0000-000000000002', 'Con'),
  ('dddddddd-8888-0000-0000-000000000003', 'Nemo')
on conflict (id) do update set first_name = excluded.first_name;

insert into public.feedback_admins (profile_id, role) values
  ('dddddddd-8888-0000-0000-000000000001', 'billing'),
  ('dddddddd-8888-0000-0000-000000000002', 'content');

insert into private.api_usage_daily (day, provider, endpoint, calls, billable_calls, errors, retries, distinct_upstream, served_flights, estimated_cost_usd) values
  (current_date, 'aeroapi', 'flights/{id}', 40, 38, 2, 1, 9, 40, 0.190000),
  (current_date, 'aeroapi', 'flights/search', 5, 5, 0, 0, 0, 5, null);

-- ---------------------------------------------------------------------------
-- The billing admin can see spend
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'dddddddd-8888-0000-0000-000000000001', true);

select ok(public.is_console_admin(), 'a billing-only admin gets through the console door');

select is(
  (select calls from public.api_usage_summary('aeroapi')),
  45::bigint, 'and can read this month'
);

select is(
  (select count(*)::integer from public.api_usage_by_endpoint('aeroapi')),
  2, 'and the per-endpoint breakdown'
);

select is(
  (select count(*)::integer from public.api_usage_daily_series('aeroapi')),
  1, 'and the daily series'
);

-- An endpoint with no rate must stay null through the aggregation. `sum` ignores nulls, so without
-- the bool_and guard `flights/search` would report 0.00 — which reads as "this endpoint is free"
-- rather than "we have never been told its price", and nobody investigates a zero.
select ok(
  (select list_cost_usd from public.api_usage_by_endpoint('aeroapi') where endpoint = 'flights/search') is null,
  'an unpriced endpoint aggregates to null, not to zero'
);

select is(
  (select list_cost_usd from public.api_usage_by_endpoint('aeroapi') where endpoint = 'flights/{id}'),
  0.190000::numeric, 'a priced one carries its cost'
);

-- 40 calls against 9 real-world flights. The duplicate-fetch ratio, which is the number that
-- decides whether deduping refresh-due-flights is worth doing.
select is(
  (select distinct_upstream from public.api_usage_by_endpoint('aeroapi') where endpoint = 'flights/{id}'),
  9::bigint, 'distinct upstream flights survive the aggregation'
);

-- ---------------------------------------------------------------------------
-- A content admin cannot
-- ---------------------------------------------------------------------------
--
-- The separation the roles exist for. Being trusted to edit a trivia deck is not being trusted
-- with what the business spends.

select set_config('request.jwt.claim.sub', 'dddddddd-8888-0000-0000-000000000002', true);

select ok(public.is_console_admin(), 'a content admin still gets through the console door');

select throws_ok(
  $$ select * from public.api_usage_summary('aeroapi') $$,
  '42501', null, 'but cannot read spend'
);

select throws_ok(
  $$ select * from public.api_usage_by_endpoint('aeroapi') $$,
  '42501', null, 'nor the endpoint breakdown'
);

-- ---------------------------------------------------------------------------
-- And nor can anybody else
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'dddddddd-8888-0000-0000-000000000003', true);

select ok(not public.is_console_admin(), 'a signed-in non-admin does not reach the console at all');

select throws_ok(
  $$ select * from public.api_usage_daily_series('aeroapi') $$,
  '42501', null, 'and is refused the usage data'
);

-- A session-less caller. `auth.uid()` is null, which must not match a row — the anon/expired-token
-- case, and it has to fail closed.
select set_config('request.jwt.claim.sub', '', true);
select ok(not public.is_console_admin(), 'no session is not an admin');

reset role;
select * from finish();
rollback;
