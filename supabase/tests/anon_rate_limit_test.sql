-- The limiter standing in front of an open mail relay.
--
-- Two properties matter more than the counting. It must not store the address it is limiting, or
-- the ledger becomes a log of who contacted support. And it must not be resettable by its own
-- caller — the mistake 20261110000200 had to unpick in `consume_rate_limit`, where the purge
-- cutoff was built from the caller's `p_window` so a one-microsecond window emptied their history.
-- This function was written after that and has to not repeat it.

begin;
select plan(11);

create extension if not exists pgtap;

set local role anon;

-- ---------------------------------------------------------------------------
-- Counting
-- ---------------------------------------------------------------------------

select ok(public.consume_anon_rate_limit('probe', '203.0.113.9', 3, interval '1 hour'), 'first is allowed');
select ok(public.consume_anon_rate_limit('probe', '203.0.113.9', 3, interval '1 hour'), 'second is allowed');
select ok(public.consume_anon_rate_limit('probe', '203.0.113.9', 3, interval '1 hour'), 'third is allowed');
select ok(not public.consume_anon_rate_limit('probe', '203.0.113.9', 3, interval '1 hour'),
  'the fourth within the window is refused');

-- A refused attempt is not written, so retrying cannot push the window out in front of the
-- caller. Same property `consume_rate_limit` documents.
reset role;
select is(
  (select count(*)::int from public.anon_rate_limit_events where bucket = 'probe'),
  3,
  'the refused attempt was not recorded'
);
set local role anon;

-- ---------------------------------------------------------------------------
-- Isolation
-- ---------------------------------------------------------------------------

select ok(public.consume_anon_rate_limit('probe', '198.51.100.4', 3, interval '1 hour'),
  'a different caller has their own budget');
select ok(public.consume_anon_rate_limit('other-probe', '203.0.113.9', 3, interval '1 hour'),
  'and the same caller has a separate budget per endpoint, because the bucket is inside the digest');

-- ---------------------------------------------------------------------------
-- The address is not in the table
-- ---------------------------------------------------------------------------

reset role;
select is(
  (select count(*)::int from public.anon_rate_limit_events
   where subject_hash like '%203.0.113.9%' or subject_hash like '%198.51.100.4%'),
  0,
  'no row contains the address it is limiting'
);

-- Salted, not a bare digest: an unsalted sha256 of an IPv4 address is reversible by enumeration,
-- which would make this ledger a record of who wrote to support.
select isnt(
  (select subject_hash from public.anon_rate_limit_events where bucket = 'probe' limit 1),
  encode(sha256('203.0.113.9'::bytea), 'hex'),
  'and the digest is salted rather than a plain hash of the address'
);

-- ---------------------------------------------------------------------------
-- The bypass this function was written after
-- ---------------------------------------------------------------------------

set local role anon;
-- Back-dated so the rows are genuinely older than `now()`; inside one transaction `now()` does
-- not advance, so a purge keyed on a tiny window has nothing to match without this.
reset role;
update public.anon_rate_limit_events set occurred_at = now() - interval '5 minutes' where bucket = 'probe';
set local role anon;

-- The attack: a legal, positive, tiny window. It is allowed, because nothing was written in the
-- last microsecond — that part is correct and expected.
select ok(
  public.consume_anon_rate_limit('probe', '203.0.113.9', 1, interval '1 microsecond'),
  'a one-microsecond window is a legal call and is permitted'
);

-- The assertion that matters, and the one the old limiter would have failed: the hour's history
-- is still there afterwards.
select ok(
  not public.consume_anon_rate_limit('probe', '203.0.113.9', 3, interval '1 hour'),
  'and it did not purge the hour''s history — the real limit is still refusing'
);

select * from finish();
rollback;
