-- ---------------------------------------------------------------------------
-- Tracked flights for the refresh cron, a page at a time (DB-4, 7-supabase-NEW-1)
-- ---------------------------------------------------------------------------
--
-- `refresh-due-flights` loaded every active couple's id, then every tracked flight with
-- `couple_id=in.(…every id…)`, and its live-position pass did the same. Two limits waited on that:
--
--   * The id list travels in the request URL, about 37 bytes a couple. Somewhere past a few hundred
--     active couples a gateway refuses the URL and the run fails outright: no refreshes, pushes,
--     Live Activity updates or positions for anyone, every minute, with only a log line to show.
--   * PostgREST stops at max_rows (1000, config.toml and the hosted default) and says nothing. Past
--     1000 active couples, or 1000 tracked flights, the rest were silently never refreshed,
--     reminded or reconciled.
--
-- This does the active-couple check in the database and pages by id, so the request is the same
-- size however many couples there are, and the caller keeps asking until a page comes back short.
-- A page is capped at 1000 so it can never be cut short by max_rows without the caller knowing.
--
-- `p_statuses` lets the live-position pass ask for airborne flights only.
-- Service role only: it reads every couple's flights.

create or replace function public.tracked_flights_page(
  p_after uuid default null,
  p_limit integer default 500,
  p_statuses text[] default null
)
returns setof public.flights
language sql
stable
security definer
set search_path = public
as $$
  select f.*
  from public.flights f
  join public.couples c on c.id = f.couple_id
  where f.tracking_enabled
    and c.status = 'active'
    and (p_after is null or f.id > p_after)
    and (p_statuses is null or f.status = any (p_statuses))
  order by f.id
  limit least(greatest(coalesce(p_limit, 500), 1), 1000);
$$;

revoke execute on function public.tracked_flights_page(uuid, integer, text[]) from public, anon, authenticated;
grant execute on function public.tracked_flights_page(uuid, integer, text[]) to service_role;

-- Pages walk tracked flights in id order; the existing partial index on tracking_enabled doesn't
-- carry the id, so each page would sort every tracked flight.
create index if not exists flights_tracked_id_idx on public.flights (id) where tracking_enabled;
