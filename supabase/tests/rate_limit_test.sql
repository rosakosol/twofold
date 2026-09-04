-- `consume_rate_limit` (20260918000000) is the only thing standing between one signed-up account
-- and an unbounded OpenAI bill or an unbounded volume of mail out of our own sending domain. It is
-- also small enough to look obviously correct while being wrong in three specific ways, so each of
-- those is pinned here rather than reasoned about:
--
--   1. A REFUSED call must not be recorded. If it were, every retry would push the window's
--      trailing edge forward and a blocked caller could hold their own lockout open indefinitely by
--      hammering — which is precisely what a blocked caller does. This is the property carried over
--      from `redeem_invite_code`, and it is invisible from the outside: the sixth call is refused
--      either way. Only the ledger shows the difference, so the ledger is what is asserted.
--
--   2. The window must actually expire. A limiter that never lets go is a limiter that bans people.
--
--   3. The window must be per caller and per bucket. A shared counter would mean one abusive
--      account locking out everyone else, and using up your support emails costing you the ability
--      to parse a flight email.
--
-- Plus the two arguments a hostile caller controls. `authenticated` holds EXECUTE on this function
-- and can call it straight through PostgREST with any arguments it likes, so the Edge Function's
-- compiled-in constants are not a constraint on anything. A negative `p_window` is the one that
-- matters: every window in the function is subtracted from `now()`, so it would turn the purge's
-- cutoff into a moment in the future and let a caller delete their own entire history — a one-line
-- reset of their own limits. That is asserted as a refusal, not commented on.
--
-- Windows here are `1 hour` with rows backdated by hand rather than anything that sleeps: the test
-- has to prove the window expires, and it cannot do that by waiting.

begin;
select plan(22);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('aaaaaaaa-6666-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ann@ratelimit.test', 'x', now(), now(), now()),
  ('bbbbbbbb-6666-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ben@ratelimit.test', 'x', now(), now(), now());

-- A trigger on auth.users already created these rows, so this fills in the fields the
-- tests care about rather than inserting fresh.
insert into public.profiles (id, first_name) values
  ('aaaaaaaa-6666-0000-0000-000000000001', 'Ann'),
  ('bbbbbbbb-6666-0000-0000-000000000002', 'Ben')
on conflict (id) do update set first_name = excluded.first_name;

-- ---------------------------------------------------------------------------
-- Everything below runs as a client role, because that is the only role the Edge Functions ever
-- reach this function through — they build a user-scoped client from the caller's own
-- Authorization header, so `auth.uid()` is the caller and the role is `authenticated`.
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-6666-0000-0000-000000000001', true);

-- The ledger itself is unreadable from a client role (RLS on, no policies), so nothing a caller can
-- select tells them how much of their budget is left, and — the half that would actually matter —
-- nothing they can DELETE gives them a one-request bypass.
select is(
  (select count(*)::int from public.rate_limit_events),
  0,
  'the ledger is invisible to the client role the Edge Functions call as'
);

-- ---------------------------------------------------------------------------
-- Under the limit: a limit of 3 admits 3.
-- ---------------------------------------------------------------------------
select is(
  (select allowed from public.consume_rate_limit('parse-flight-email', 3, interval '1 hour')),
  true,
  'the first call under the limit is allowed'
);
select is(
  (select allowed from public.consume_rate_limit('parse-flight-email', 3, interval '1 hour')),
  true,
  'and the second'
);
select is(
  (select allowed from public.consume_rate_limit('parse-flight-email', 3, interval '1 hour')),
  true,
  'and the third, which is the last one the limit permits'
);
select is(
  (select retry_after_seconds from public.consume_rate_limit('parse-flight-email', 10, interval '1 hour')),
  0,
  'an admitted call reports no retry delay'
);

-- ---------------------------------------------------------------------------
-- Over the limit. (The call above used a limit of 10, so four rows are now in the bucket.)
-- ---------------------------------------------------------------------------
select is(
  (select allowed from public.consume_rate_limit('parse-flight-email', 3, interval '1 hour')),
  false,
  'the call past the limit is refused'
);

-- The earliest slot frees up when the oldest of the four rows ages out, which is just under an hour
-- away — so this is bounded above by the window and, per the `greatest(..., 1)` in the function,
-- never 0. `Retry-After: 0` would read as "go again now", the opposite of what was just said.
select ok(
  (select retry_after_seconds from public.consume_rate_limit('parse-flight-email', 3, interval '1 hour'))
    between 1 and 3600,
  'a refused call reports a real Retry-After inside the window, never 0'
);

-- ---------------------------------------------------------------------------
-- The property this whole file exists for: a refused call is not recorded.
-- ---------------------------------------------------------------------------
reset role;
select is(
  (select count(*)::int from public.rate_limit_events
   where user_id = 'aaaaaaaa-6666-0000-0000-000000000001' and bucket = 'parse-flight-email'),
  4,
  'only the four admitted calls were logged — the two refusals above left no trace'
);
set local role authenticated;

-- Hammering, which is what a blocked caller actually does. If refusals were logged this would be
-- 4 + 6 rows and the window's trailing edge would have moved six calls further into the future,
-- extending the lockout by exactly the retrying.
select is(
  (select allowed from public.consume_rate_limit('parse-flight-email', 3, interval '1 hour')),
  false,
  'a blocked caller stays blocked while hammering'
);
select is((select allowed from public.consume_rate_limit('parse-flight-email', 3, interval '1 hour')), false, 'still blocked');
select is((select allowed from public.consume_rate_limit('parse-flight-email', 3, interval '1 hour')), false, 'still blocked');
select is((select allowed from public.consume_rate_limit('parse-flight-email', 3, interval '1 hour')), false, 'still blocked');
select is((select allowed from public.consume_rate_limit('parse-flight-email', 3, interval '1 hour')), false, 'still blocked');

reset role;
select is(
  (select count(*)::int from public.rate_limit_events
   where user_id = 'aaaaaaaa-6666-0000-0000-000000000001' and bucket = 'parse-flight-email'),
  4,
  'and the ledger is still 4 — retrying cannot extend the caller''s own lockout'
);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- Buckets are separate budgets.
-- ---------------------------------------------------------------------------
select is(
  (select allowed from public.consume_rate_limit('submit-help-message', 5, interval '1 hour')),
  true,
  'the same caller, exhausted in one bucket, is untouched in another'
);

-- ---------------------------------------------------------------------------
-- Callers are separate budgets. Ben, in Ann's exhausted bucket.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'bbbbbbbb-6666-0000-0000-000000000002', true);
select is(
  (select allowed from public.consume_rate_limit('parse-flight-email', 3, interval '1 hour')),
  true,
  'a second caller is unaffected by the first having exhausted the same bucket'
);
reset role;
select is(
  (select count(*)::int from public.rate_limit_events
   where user_id = 'aaaaaaaa-6666-0000-0000-000000000001' and bucket = 'parse-flight-email'),
  4,
  'and their call did not land in the first caller''s ledger'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-6666-0000-0000-000000000001', true);

-- ---------------------------------------------------------------------------
-- The window expires — and takes the dead rows with it.
-- ---------------------------------------------------------------------------
reset role;
update public.rate_limit_events
set occurred_at = now() - interval '2 hours'
where user_id = 'aaaaaaaa-6666-0000-0000-000000000001' and bucket = 'parse-flight-email';
set local role authenticated;

select is(
  (select allowed from public.consume_rate_limit('parse-flight-email', 3, interval '1 hour')),
  true,
  'once the window has passed, the caller is admitted again'
);

-- Retention, and the reason it is in the RPC rather than in a cron job nobody would remember to
-- write: `invite_redemption_attempts` has kept every row since 20260829000600 because nothing ever
-- deletes from it. The four expired rows here are gone, leaving only the call just admitted.
reset role;
select is(
  (select count(*)::int from public.rate_limit_events
   where user_id = 'aaaaaaaa-6666-0000-0000-000000000001' and bucket = 'parse-flight-email'),
  1,
  'and the expired rows were purged, so the ledger does not grow forever'
);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- The two arguments a caller controls, and the caller identity they do not.
-- ---------------------------------------------------------------------------

-- The bypass. `now() - interval '-1 hour'` is an hour into the future, so the purge's
-- `occurred_at <= cutoff` would match every row the caller has and hand them a clean slate.
select throws_ok(
  $$select * from public.consume_rate_limit('parse-flight-email', 3, interval '-1 hour')$$,
  'P0001',
  null,
  'a negative window is refused — it would invert the purge cutoff and wipe the caller''s own history'
);

select throws_ok(
  $$select * from public.consume_rate_limit('parse-flight-email', 0, interval '1 hour')$$,
  'P0001',
  null,
  'a limit below 1 is refused rather than silently admitting or blocking everything'
);

-- There is no caller to attribute usage to, so there is nothing to limit — and every real call
-- arrives through a user-scoped client, so reaching here at all is a bug in the caller. Same
-- treatment as `redeem_invite_code`'s 'Not authenticated'.
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select * from public.consume_rate_limit('parse-flight-email', 3, interval '1 hour')$$,
  'P0001',
  'Not authenticated',
  'an unauthenticated caller is refused outright'
);

select * from finish();
rollback;
