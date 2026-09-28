-- ---------------------------------------------------------------------------
-- The subscription gate stopped one table short of the expensive one
-- ---------------------------------------------------------------------------
--
-- 20261028000000 moved "adding needs a subscription" out of the paywall screen and into the
-- database, and gated every table a client can write: trips, memories, memory photos, flight
-- documents, flight updates, game responses, invite codes. It did not gate flights, and could not
-- have: no policy grants clients INSERT on `public.flights` at all. They are written by
-- `add-flight` as service_role, and tracking is switched on by this function — so a gate expressed
-- as RLS never touches either one.
--
-- The result was that the one kind of content which costs real money was the only kind a lapsed
-- couple could still add. `flight_limit_for_tier` floors at the plus allowance of five and
-- `couple_effective_tier` falls back to 'plus' for a couple with no subscription at all, so a
-- couple who had stopped paying got five live-tracked flights a month, indefinitely — roughly 85c
-- of AeroAPI polling each, billed again on every poll for the life of the flight. Every other
-- kind of adding was refused; this one was free.
--
-- Placed after the `flight_over` check on purpose, so the two answers that cost nothing further are
-- unchanged for somebody who has lapsed: a flight already being tracked still reports
-- `already_tracking`, and one that has already landed still reports `flight_over`. What is refused
-- is only ever the start of new polling.
--
-- `couple_is_subscribed` rather than the caller's own row, for the reason that function exists: one
-- subscription covers both partners, and the non-paying half must not be refused what their partner
-- bought.
--
-- Replaced whole, as 20261018000000 did for the same function — `create or replace function` has no
-- way to change one line. Everything but the new check is carried across unchanged.

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
  'most one slot ever, and a flight that has already arrived spends none.';
