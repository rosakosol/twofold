-- ---------------------------------------------------------------------------
-- A flight that has already flown spends no tracking slot, even when its status never moved
-- ---------------------------------------------------------------------------
--
-- `enable_flight_tracking` decided "flight over" from the status text and the cancelled/diverted
-- flags alone. A flight saved without tracking gets no status updates, so it is still 'scheduled'
-- after it has landed — and for that flight the function switched tracking on and recorded a
-- `flight_additions` row, spending one of the couple's monthly slots on a flight that was over. Its
-- own comment says a flight that has already arrived spends none (3-flights-NEW-1). The app offered
-- it on exactly those flights (FLT-10), and now doesn't.
--
-- The clock decides as well, with the same best-known time the app uses (`Flight.bestArrival ??
-- Flight.bestDeparture`, see `Flight.isOver`): arrival actual, estimated, scheduled, then the
-- wheels-down family, and only with no arrival time at all, the departure. A flight in the air is
-- not over; one whose arrival has passed is, whatever its status still says. Answered as
-- `flight_over`, which the app already explains.
--
-- Replaced whole, as 20261110001800 did — `create or replace function` has no way to change one
-- line. Everything but the new `v_reference` check is carried across unchanged.

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
  v_reference timestamptz;
  v_limit integer;
  v_used integer;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select couple_id, status, cancelled, diverted, tracking_enabled,
         coalesce(
           actual_in, estimated_in, scheduled_in, actual_on, estimated_on, scheduled_on,
           actual_out, estimated_out, scheduled_out, actual_off, estimated_off, scheduled_off
         )
    into v_couple_id, v_status, v_cancelled, v_diverted, v_enabled, v_reference
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

  -- The status alone can't say a flight is over when nothing has been updating it. See the header.
  if v_reference is not null and v_reference <= now() then
    return jsonb_build_object('enabled', false, 'reason', 'flight_over');
  end if;

  -- A refusal, not an exception. Every other outcome of this function is reported rather than
  -- raised, and the caller renders the reason — a throw here would reach the app as a generic
  -- failure and be shown as "couldn't turn tracking on", which is the one reading that does not
  -- tell somebody what to do about it.
  if not public.couple_is_subscribed(v_couple_id) then
    return jsonb_build_object('enabled', false, 'reason', 'subscription_required');
  end if;

  v_limit := private.flight_limit_for_couple(v_couple_id);
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

revoke all on function public.enable_flight_tracking(uuid) from public, anon;
grant execute on function public.enable_flight_tracking(uuid) to authenticated;

comment on function public.enable_flight_tracking(uuid) is
  'Spends one of the couple''s monthly live-tracking slots to start polling a flight that was '
  'added without it. Membership-checked, and subscription-checked: starting new polling is adding '
  'to the couple''s story, which is what a subscription buys (20261028000000). A flight spends at '
  'most one slot ever, and a flight that has already arrived spends none — by its status, or by the '
  'clock when nothing has been updating its status (20261117000400).';
