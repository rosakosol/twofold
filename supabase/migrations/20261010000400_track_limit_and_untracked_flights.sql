-- ---------------------------------------------------------------------------
-- The allowance caps live tracking, not flights
-- ---------------------------------------------------------------------------
--
-- Adding a flight costs about 2c: one search call, one lookup, two airport coordinate lookups.
-- Tracking it to the gate costs about 85c — status polling, weather, delay stats. A 40x gap.
--
-- The old limit capped the cheap thing to control the expensive one, which meant a couple who had
-- used their allowance could not record a trip at all. That does not just withhold tracking: a
-- flight is what Passport stats, trip history and the Relationship Record are built from, so the
-- limit was capping the couple's own record of their life over a cost of two cents.
--
-- So the cap moves onto tracking. Flights past it are still added, kept and shown — they are
-- simply not polled, and get no notifications or Live Activity. `flights.tracking_enabled` already
-- existed for exactly this shape and `refresh-due-flights` already excludes it, so nothing in the
-- cron changes.
--
-- New limits: 2/month on Plus, 5/month on Premium, down from 5 and 20.

create or replace function public.flight_limit_for_tier(p_tier text)
returns integer
language sql
immutable
as $$
  select case when p_tier = 'premium' then 5 else 2 end;
$$;

comment on function public.flight_limit_for_tier(text) is
  'Live-tracked flights per calendar month per couple, by tier. Flights beyond it can still be '
  'added, untracked. Mirrors the paywall copy in SubscriptionStore.swift.';

comment on table public.flight_additions is
  'Append-only record of every flight a couple has ever put into live tracking, used for the '
  'shared monthly allowance. The row outlives the flight it recorded, so deleting a flight never '
  'refunds its slot. One row per flight at most, ever — see enable_flight_tracking.';

-- ---------------------------------------------------------------------------
-- Turning tracking on for a flight that does not have it
-- ---------------------------------------------------------------------------
--
-- The allowance is now spent here rather than at add time, because this is the moment the expense
-- actually starts. `add-flight` still spends one directly when a couple is under the limit, so the
-- common path is unchanged; this covers the flight that was added untracked and is now wanted.
--
-- Two rules worth stating, because both are ways this could quietly overcharge someone:
--
--   * A flight spends at most one slot in its entire life. `tracking_enabled` is cleared by the
--     system in the ordinary course of things — two hours after arrival, on dissolution, on a
--     lapsed subscription — and without the guard below, re-enabling any of those would charge a
--     second time for one flight.
--   * A flight that has already arrived cannot be tracked. There is nothing left to poll, so
--     spending a slot on it would buy the couple precisely nothing.
create or replace function public.enable_flight_tracking(p_flight_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_couple_id uuid;
  v_status text;
  v_cancelled boolean;
  v_diverted boolean;
  v_enabled boolean;
  v_tier text;
  v_limit integer;
  v_used integer;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select couple_id, status, cancelled, diverted, tracking_enabled
    into v_couple_id, v_status, v_cancelled, v_diverted, v_enabled
  from public.flights
  where id = p_flight_id;

  -- Not found and not yours are the same answer on purpose: distinguishing them would confirm
  -- whether a given flight id exists to someone who cannot see it.
  if v_couple_id is null or not public.is_couple_member(v_couple_id) then
    raise exception 'No such flight' using errcode = '42501';
  end if;

  if v_enabled then
    return jsonb_build_object('enabled', true, 'already_tracking', true);
  end if;

  -- Mirrors ARRIVAL_TERMINAL_STATUSES in _shared/flight-schedule.ts, which is what the cron uses
  -- to decide a flight is done with. The two booleans are checked as well because the columns
  -- exist independently of the status text and a row can carry one without the other.
  if v_cancelled or v_diverted or v_status in ('landed', 'arrived', 'cancelled', 'diverted') then
    return jsonb_build_object('enabled', false, 'reason', 'flight_over');
  end if;

  v_tier := private.couple_effective_tier(v_couple_id);
  v_limit := public.flight_limit_for_tier(v_tier);
  v_used := public.flights_used_this_month(v_couple_id);

  -- Already paid for in a previous life (archived after arrival, then somehow re-offered). Costs
  -- nothing further, so it does not need to pass the limit.
  if exists (select 1 from public.flight_additions where flight_id = p_flight_id) then
    update public.flights set tracking_enabled = true where id = p_flight_id;
    return jsonb_build_object('enabled', true, 'limit', v_limit, 'used', v_used);
  end if;

  if v_used >= v_limit then
    return jsonb_build_object('enabled', false, 'reason', 'limit_reached', 'limit', v_limit, 'used', v_used);
  end if;

  update public.flights set tracking_enabled = true where id = p_flight_id;
  insert into public.flight_additions (couple_id, flight_id, added_by)
  values (v_couple_id, p_flight_id, v_me);

  return jsonb_build_object('enabled', true, 'limit', v_limit, 'used', v_used + 1);
end;
$$;

revoke all on function public.enable_flight_tracking(uuid) from public;
grant execute on function public.enable_flight_tracking(uuid) to authenticated;

comment on function public.enable_flight_tracking(uuid) is
  'Spends one of the couple''s monthly live-tracking slots to start polling a flight that was '
  'added without it. Membership-checked. A flight spends at most one slot ever, and a flight that '
  'has already arrived spends none.';
