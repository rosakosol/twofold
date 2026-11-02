-- One flight refresh run at a time (DB-5).
--
-- pg_cron fires `refresh-due-flights` every minute through net.http_post, which does not wait for
-- the previous call. A run that takes longer than a minute overlapped the next one, and both
-- worked through the same flights: two AeroAPI bills per flight, and two reminder pushes.
--
-- A session advisory lock can't be held across an edge function's PostgREST calls (each one is a
-- transaction on a pooled connection), so the run holds a lease row instead: claimed at the start,
-- released at the end, and expiring on its own if the run dies without releasing it.

begin;
select plan(10);

select is(
  public.claim_cron_lease('refresh-due-flights', 120) is not null,
  true,
  'the first run gets the lease'
);

create temporary table first_holder as
select holder from private.cron_leases where job = 'refresh-due-flights';

select is(
  public.claim_cron_lease('refresh-due-flights', 120),
  null,
  'a second run while the first holds it gets nothing'
);

select is(
  public.claim_cron_lease('archive-stale-games', 120) is not null,
  true,
  'another job''s lease is its own'
);

select is(
  public.release_cron_lease('refresh-due-flights', gen_random_uuid()),
  false,
  'only the holder can release the lease'
);

select is(
  public.release_cron_lease('refresh-due-flights', (select holder from first_holder)),
  true,
  'the holder releases it'
);

select is(
  public.claim_cron_lease('refresh-due-flights', 120) is not null,
  true,
  'the next run gets it once released'
);

-- A run that died without releasing: its lease ran out a second ago.
update private.cron_leases set locked_until = now() - interval '1 second' where job = 'refresh-due-flights';

select is(
  public.claim_cron_lease('refresh-due-flights', 120) is not null,
  true,
  'an expired lease is taken over'
);

select throws_ok(
  $$ select public.claim_cron_lease('refresh-due-flights', 0) $$,
  '22023',
  null,
  'a lease must last at least a second'
);

select is(
  has_function_privilege('authenticated', 'public.claim_cron_lease(text, integer)', 'execute'),
  false,
  'a signed-in user cannot take the cron''s lease'
);

select is(
  has_function_privilege('anon', 'public.release_cron_lease(text, uuid)', 'execute'),
  false,
  'nor can anon release it'
);

select * from finish();
rollback;
