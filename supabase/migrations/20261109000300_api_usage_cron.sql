-- ---------------------------------------------------------------------------
-- Rolling up usage, and throwing the raw rows away
-- ---------------------------------------------------------------------------
--
-- Pure SQL, like `expire-stale-move-games` and `purge-expired-couple-archives`: there is nothing
-- to notify and nobody to call, so this needs none of the pg_net/Vault plumbing the jobs that hit
-- an edge function carry.
--
-- ---------------------------------------------------------------------------
-- Hourly, not nightly
-- ---------------------------------------------------------------------------
--
-- The obvious schedule is one nightly pass over yesterday. It would also make the console a day
-- stale, which defeats most of the point: the number worth having is today's, while there is still
-- a day left to react to it. The 2-minute cruise tier that `refresh-due-flights` was eventually
-- caught spending on would have been just as invisible on a dashboard that only showed yesterday.
--
-- So it runs hourly, and each run restates today AND yesterday. Restating yesterday every hour
-- costs nothing -- it is one bounded aggregate over a day's rows, upserted -- and it closes two
-- gaps that a single midnight pass leaves open: a row written a moment before midnight and
-- committed a moment after, and a rate corrected the following day.
--
-- Idempotence is what makes this safe, and it is pinned by api_usage_metering_test.
--
-- ---------------------------------------------------------------------------
-- Which midnight
-- ---------------------------------------------------------------------------
--
-- `current_date` is the database's, which is UTC. So "today" in the console rolls over at 10am or
-- 11am in Australia, not at local midnight. That is deliberate rather than overlooked: the
-- alternative is picking a local day boundary that matches neither the database nor FlightAware's
-- own billing period, and a spend figure whose window nobody can state precisely is worse than one
-- that resets at a slightly odd hour. The console labels it a UTC day.
--
-- ---------------------------------------------------------------------------
-- Timing
-- ---------------------------------------------------------------------------
--
-- At :05 rather than on the hour. `refresh-due-flights` runs every minute and the streak jobs run
-- at :00, :15, :30 and :45; the dormancy migration's own note applies here too -- two jobs on the
-- same minute is how one of them starts timing out.
--
-- The purge runs at 05:30, in a slot nothing else uses. 03:00 and 04:00 each already carry two
-- daily jobs.

-- Restates the two days that can still change. Returns the number of rollup rows written, summed
-- across both, which is what shows up in `cron.job_run_details` when someone is working out
-- whether this job is doing anything.
create or replace function private.roll_up_recent_api_usage()
returns integer
language sql
security definer
set search_path = private, public
as $$
  select coalesce(private.roll_up_api_usage(current_date), 0)
       + coalesce(private.roll_up_api_usage(current_date - 1), 0);
$$;

comment on function private.roll_up_recent_api_usage() is
  'Rolls up today and yesterday. Runs hourly from pg_cron so the console shows spend while there '
  'is still a day left to act on it, rather than only through yesterday.';

-- Consistent with `expire_stale_move_games` and `purge_expired_couple_archives`: these are cron''s
-- to call and nobody else''s. `private` is already unreachable over PostgREST, so this is the same
-- belt-and-braces those functions wear -- the protection is a line in config.toml somewhere else,
-- and an explicit revoke is what survives that line changing.
revoke all on function private.roll_up_recent_api_usage() from public, anon, authenticated;
revoke all on function private.roll_up_api_usage(date) from public, anon, authenticated;
revoke all on function private.purge_api_usage_events(integer) from public, anon, authenticated;

select cron.schedule(
  'roll-up-api-usage',
  '5 * * * *',
  'select private.roll_up_recent_api_usage();'
);

select cron.schedule(
  'purge-api-usage-events',
  '30 5 * * *',
  'select private.purge_api_usage_events();'
);
