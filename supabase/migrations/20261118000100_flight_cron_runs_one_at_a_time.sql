-- ---------------------------------------------------------------------------
-- One flight refresh run at a time (DB-5)
-- ---------------------------------------------------------------------------
--
-- pg_cron fires `refresh-due-flights` every minute (20260826000000) through net.http_post, which
-- does not wait for the previous call to finish. A run that took longer than a minute overlapped
-- the next, and both worked through the same flights from the same stale reads: two AeroAPI calls
-- billed per flight, and both runs passing the "reminder not sent yet" check and sending it.
--
-- The obvious tool is pg_try_advisory_lock, but it can't be held by an edge function: each
-- PostgREST call is its own transaction on a pooled connection, so a transaction lock is gone as
-- soon as the claiming call returns, and a session lock stays on whichever pooled connection
-- happened to serve it. So the run holds a lease row instead. It claims the lease before touching
-- any flight, releases it when done, and a run that dies without releasing it (a timeout, a
-- deploy) loses it when `locked_until` passes, so one crash can't stop flight tracking for good.
--
-- Generic over `job` so the other every-few-minutes jobs can use the same lease if they need one.
-- Service role only: a signed-in user who could take the lease could stop flight tracking.

create table private.cron_leases (
  job text primary key,
  holder uuid not null,
  locked_until timestamptz not null
);

revoke all on private.cron_leases from public, anon, authenticated;

comment on table private.cron_leases is
  'One row per cron job currently running. See claim_cron_lease / release_cron_lease.';

-- Returns the new holder id, or null when another run holds an unexpired lease. Two runs claiming
-- at once serialise on the primary key: the second sees the first's row and its `where` fails.
create or replace function public.claim_cron_lease(p_job text, p_ttl_seconds integer)
returns uuid
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_holder uuid := gen_random_uuid();
  v_claimed uuid;
begin
  if p_job is null or p_ttl_seconds is null or p_ttl_seconds < 1 or p_ttl_seconds > 3600 then
    raise exception 'claim_cron_lease: a job name and a lease of 1 to 3600 seconds are required'
      using errcode = '22023';
  end if;

  insert into private.cron_leases as l (job, holder, locked_until)
  values (p_job, v_holder, clock_timestamp() + make_interval(secs => p_ttl_seconds))
  on conflict (job) do update
    set holder = excluded.holder, locked_until = excluded.locked_until
    where l.locked_until <= clock_timestamp()
  returning holder into v_claimed;

  return v_claimed;
end;
$$;

-- Only the holder can release, so a run that outlived its lease can't free the next run's.
create or replace function public.release_cron_lease(p_job text, p_holder uuid)
returns boolean
language plpgsql
security definer
set search_path = private, public
as $$
begin
  delete from private.cron_leases where job = p_job and holder = p_holder;
  return found;
end;
$$;

revoke execute on function public.claim_cron_lease(text, integer) from public, anon, authenticated;
revoke execute on function public.release_cron_lease(text, uuid) from public, anon, authenticated;
grant execute on function public.claim_cron_lease(text, integer) to service_role;
grant execute on function public.release_cron_lease(text, uuid) to service_role;
