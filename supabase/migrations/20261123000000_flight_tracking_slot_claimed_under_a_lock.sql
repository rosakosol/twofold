-- ---------------------------------------------------------------------------
-- A tracking slot is claimed under a lock, so requests sent together cannot all fit
-- ---------------------------------------------------------------------------
--
-- Both ways of spending a monthly tracking slot read the month's usage, decided, and wrote the
-- ledger row later, with nothing between the read and the write:
--
--   * add-flight read `flight_allowance`, made its AeroAPI lookups, inserted the flight with
--     `tracking_enabled` set from that read, and then called `record_flight_addition`, which
--     always inserts.
--   * `enable_flight_tracking` counted, compared, and inserted, in three statements.
--
-- Requests sent at once all read the same count. 20260930000000 accepted that as "one flight over
-- for the month" — but nothing bounds it at one: against the local stack, six adds fired together
-- by a couple on Plus's two-flight allowance tracked five or six of them, and six parallel
-- `enable_flight_tracking` calls did the same (functions/_shared/flight-allowance-races.test.ts).
-- At ~85c of polling per tracked flight, the allowance was a matter of how fast someone could tap.
--
-- So the check and the write become one step, taken under a transaction-scoped advisory lock
-- keyed on the couple: the second request waits for the first to commit, then counts again and
-- sees its row. An advisory lock rather than `select ... for update` on `couples` because the count
-- reads `flight_additions`, not the couple row, and locking the couple row would also block every
-- unrelated update to it (status, streaks) for the length of the claim. Keyed by couple rather than
-- by each partner because a person is in one active couple at a time, and one key cannot deadlock
-- against another the way two per-person locks taken in different orders could.
--
-- ---------------------------------------------------------------------------
-- When add-flight claims, and why that is after the insert
-- ---------------------------------------------------------------------------
--
-- add-flight now inserts every flight untracked and then calls `claim_flight_tracking_slot`, which
-- switches tracking on and writes the ledger row only if the couple is within the allowance —
-- both in the one transaction, under the lock.
--
-- Claiming before the AeroAPI lookups was considered and is not what this does. Those lookups are
-- made whether or not the flight ends up tracked (an over-allowance add still saves, untracked —
-- 20261010000400), so claiming first would save nothing on them; what the allowance meters is the
-- polling, and polling only starts when `tracking_enabled` turns true, which now only this
-- function does. Claiming first would also need a refund for every lookup that failed after the
-- slot was taken. Claiming after the row exists needs none: a claim that fails leaves an untracked
-- flight and no ledger row, and add-flight deletes that flight and asks the client to retry, so
-- nothing is spent and nothing is half-saved.
--
-- The count is `flights_used_this_month`, unchanged: it counts the two partners' additions, not
-- the couple row's (20261004000000), so re-pairing still does not reset the month.

create or replace function private.spend_flight_tracking_slot(
  p_couple_id uuid,
  p_flight_id uuid,
  p_added_by uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit integer;
  v_used integer;
begin
  -- Held to the end of the caller's transaction, so the ledger row below is committed before the
  -- next claim for this couple can count.
  perform pg_advisory_xact_lock(hashtext('flight_allowance:' || p_couple_id::text));

  -- Read after the lock, not before: under READ COMMITTED each statement sees what had committed
  -- when it started, which is now everything the previous holder wrote.
  v_limit := private.flight_limit_for_couple(p_couple_id);
  v_used := public.flights_used_this_month(p_couple_id);

  -- Already paid for (a flight spends at most one slot in its life — 20261010000400). Checked under
  -- the lock too, or two claims for the same flight could each see no row and each write one.
  if exists (select 1 from public.flight_additions where flight_id = p_flight_id) then
    update public.flights set tracking_enabled = true where id = p_flight_id;
    return jsonb_build_object('enabled', true, 'limit', v_limit, 'used', v_used);
  end if;

  if v_used >= v_limit then
    return jsonb_build_object('enabled', false, 'reason', 'limit_reached', 'limit', v_limit, 'used', v_used);
  end if;

  update public.flights set tracking_enabled = true where id = p_flight_id;
  insert into public.flight_additions (couple_id, flight_id, added_by)
  values (p_couple_id, p_flight_id, p_added_by);

  return jsonb_build_object('enabled', true, 'limit', v_limit, 'used', v_used + 1);
end;
$$;

revoke all on function private.spend_flight_tracking_slot(uuid, uuid, uuid) from public, anon, authenticated;

comment on function private.spend_flight_tracking_slot(uuid, uuid, uuid) is
  'The one place a monthly live-tracking slot is spent: count, compare, record and switch tracking '
  'on, under a per-couple advisory lock so concurrent claims cannot all fit (20261123000000). '
  'Authorises nothing; its two callers do that first.';

-- ---------------------------------------------------------------------------
-- add-flight's claim
-- ---------------------------------------------------------------------------
--
-- Answers `tracking` rather than `enabled` because that is the field add-flight already returns to
-- the app, and `tier` so a caller has the whole allowance from one call. The couple comes from the
-- flight row rather than an argument, so the claim cannot be pointed at a different couple's
-- allowance than the flight it turns on.
create or replace function public.claim_flight_tracking_slot(p_flight_id uuid, p_added_by uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple_id uuid;
  v_result jsonb;
begin
  select couple_id into v_couple_id from public.flights where id = p_flight_id;
  if v_couple_id is null then
    raise exception 'No such flight' using errcode = 'P0002';
  end if;

  v_result := private.spend_flight_tracking_slot(v_couple_id, p_flight_id, p_added_by);
  return jsonb_build_object(
    'tracking', (v_result ->> 'enabled')::boolean,
    'limit', v_result -> 'limit',
    'used', v_result -> 'used',
    'tier', private.couple_effective_tier(v_couple_id)
  );
end;
$$;

-- From anon and authenticated by name as well as from public: Supabase's default privileges hand
-- each new function its own grant to both (20261108000000).
revoke all on function public.claim_flight_tracking_slot(uuid, uuid) from public, anon, authenticated;
grant execute on function public.claim_flight_tracking_slot(uuid, uuid) to service_role;

comment on function public.claim_flight_tracking_slot(uuid, uuid) is
  'add-flight''s claim on a monthly live-tracking slot for a flight it has just saved untracked. '
  'Tracks it and records the slot only within the allowance, atomically (20261123000000). '
  'service_role only — a client that could call this could pick whose flight to charge.';

comment on function public.record_flight_addition(uuid, uuid, uuid) is
  'Records that a couple added a flight, unconditionally. No longer called by add-flight, which '
  'claims through claim_flight_tracking_slot instead (20261123000000). service_role only.';

-- ---------------------------------------------------------------------------
-- enable_flight_tracking
-- ---------------------------------------------------------------------------
--
-- Replaced whole, as 20261117000400 did. Everything up to the allowance is carried across
-- unchanged; the count, the already-paid check and the write move into
-- `private.spend_flight_tracking_slot`, so they happen under the lock.

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

  -- The status alone can't say a flight is over when nothing has been updating it. See 20261117000400.
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

  -- Same answers as before — {enabled, limit, used}, or {enabled: false, reason: 'limit_reached',
  -- limit, used} — now decided under the lock. See this migration's header.
  return private.spend_flight_tracking_slot(v_couple_id, p_flight_id, v_me);
end;
$$;

revoke all on function public.enable_flight_tracking(uuid) from public, anon;
grant execute on function public.enable_flight_tracking(uuid) to authenticated;

comment on function public.enable_flight_tracking(uuid) is
  'Spends one of the couple''s monthly live-tracking slots to start polling a flight that was '
  'added without it. Membership-checked, and subscription-checked: starting new polling is adding '
  'to the couple''s story, which is what a subscription buys (20261028000000). A flight spends at '
  'most one slot ever, and a flight that has already arrived spends none — by its status, or by the '
  'clock when nothing has been updating its status (20261117000400). The slot is claimed under a '
  'per-couple lock, so concurrent calls cannot overspend the allowance (20261123000000).';
