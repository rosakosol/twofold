-- ---------------------------------------------------------------------------
-- The monthly flight limit the paywall has been promising all along
-- ---------------------------------------------------------------------------
--
-- "Track up to 5 flights each month" and "up to 20" are printed on the paywall and were enforced
-- nowhere: no client check, no server check, no counter. Anyone on Plus could track any number of
-- flights, and every one of them costs real money — AeroAPI on lookup, and again on every poll for
-- the life of the flight.
--
-- Three things this has to get right, all of them stated by the product rather than inferred:
--
--   1. The allowance is per COUPLE, not per person. Two partners share one subscription, so they
--      share its flights. Counting per profile would silently double it.
--
--   2. A deleted flight still counts. "Any flight that is ever added, even on accident, counts
--      towards the monthly limit." That rules out `count(*) from flights` — deleting one would
--      hand the slot back, which turns the limit into a suggestion. Hence an append-only ledger:
--      `flight_additions` records the act of adding, and nothing removes those rows.
--
--   3. A calendar month, resetting on the 1st. Not a rolling 30 days: the copy says "each month",
--      and a limit whose reset date nobody can predict is a support ticket rather than a feature.
--      Measured in UTC, so both partners get the same answer regardless of where each of them is.
--
-- Keyed on `couple_id`, which is what makes "a re-paired couple starts fresh" fall out for free:
-- re-pairing mints a new couples row, so its ledger is empty with no extra logic. (If a future
-- change revives the dissolved row on re-pair instead, that decision also revives the month's
-- usage — deliberately flagged here, because the two would otherwise silently couple together.)

create table public.flight_additions (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples (id) on delete cascade,
  -- Nulled rather than deleted when the flight goes, which is the entire point of this table: the
  -- row outlives the flight it recorded, so the slot stays spent.
  flight_id uuid references public.flights (id) on delete set null,
  added_by uuid not null references public.profiles (id) on delete cascade,
  added_at timestamptz not null default now()
);

create index flight_additions_couple_month_idx
  on public.flight_additions (couple_id, added_at desc);

alter table public.flight_additions enable row level security;

-- Readable by the couple, so the app can show "3 of 5 used this month" before someone starts a
-- search that is going to be refused. Deliberately no insert/update/delete policy for clients:
-- this is written only by `add-flight` as service_role. A client that could write its own ledger
-- rows could also not write them, which is the same as having no limit.
create policy "flight_additions_select_members" on public.flight_additions
  for select using (public.is_couple_member(couple_id));

comment on table public.flight_additions is
  'Append-only record of every flight ever added by a couple, used for the shared monthly limit. '
  'Rows are never deleted when a flight is: a deleted flight still counts against the month.';

-- ---------------------------------------------------------------------------
-- The allowance
-- ---------------------------------------------------------------------------

create or replace function public.flight_limit_for_tier(p_tier text)
returns integer
language sql
immutable
as $$
  select case when p_tier = 'premium' then 20 else 5 end;
$$;

comment on function public.flight_limit_for_tier(text) is
  'Flights per calendar month per couple, by tier. Mirrors the paywall copy in SubscriptionStore.swift.';

-- ---------------------------------------------------------------------------
-- Usage, and the claim
-- ---------------------------------------------------------------------------

-- Read-only. Used by `flight_allowance` below, and through it by the app and by `add-flight`.
create or replace function public.flights_used_this_month(p_couple_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
  from public.flight_additions
  where couple_id = p_couple_id
    and added_at >= date_trunc('month', now() at time zone 'utc');
$$;

-- Usage and allowance together, for callers that need to decide before acting.
--
-- One function rather than exposing the pieces: the tier comes from `private.couple_effective_tier`,
-- which is in a schema PostgREST does not serve, so a caller could otherwise read the count but not
-- what to compare it against. Readable by the couple, so the app can show remaining allowance
-- without a round trip through an edge function.
create or replace function public.flight_allowance(p_couple_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tier text;
begin
  if not public.is_couple_member(p_couple_id) then
    raise exception 'not a member of this couple' using errcode = '42501';
  end if;

  v_tier := private.couple_effective_tier(p_couple_id);
  return jsonb_build_object(
    'tier', v_tier,
    'limit', public.flight_limit_for_tier(v_tier),
    'used', public.flights_used_this_month(p_couple_id)
  );
end;
$$;

comment on function public.flight_allowance(uuid) is
  'This couple''s monthly flight allowance and how much of it is spent. Membership-checked, so it '
  'is safe to expose to the client — the tier itself comes from a schema PostgREST does not serve.';

-- Records an addition. Always inserts.
--
-- Deliberately not a check-and-insert. By the time this is called the flight exists and is being
-- tracked, and the rule is that any flight ever added counts — so a row that refused to record
-- itself because the couple was already at the limit would produce exactly the thing the ledger
-- exists to prevent: a tracked flight nobody is charged for.
--
-- The limit is enforced ahead of this, by `flight_allowance`, before `add-flight` spends anything
-- at the provider. Two simultaneous adds can both pass that read and both land here, putting a
-- couple one over for the month. That is accepted rather than locked against: this is a commercial
-- allowance, not a security boundary, and the cost of being one over is one flight's polling —
-- against the cost of a reservation protocol that has to compensate every failed lookup.
create or replace function public.record_flight_addition(
  p_couple_id uuid,
  p_flight_id uuid,
  p_added_by uuid
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.flight_additions (couple_id, flight_id, added_by)
  values (p_couple_id, p_flight_id, p_added_by);
$$;

-- From `public`, not from `anon, authenticated`. Postgres grants EXECUTE to PUBLIC on every new
-- function, and revoking from the two client roles leaves that blanket grant standing — the
-- function stays callable by exactly the people it was being locked away from. Every other revoke
-- in this repo says `from public`; this one said otherwise until a test called it as a signed-in
-- client and it went through.
revoke all on function public.record_flight_addition(uuid, uuid, uuid) from public;
grant execute on function public.record_flight_addition(uuid, uuid, uuid) to service_role;

comment on function public.record_flight_addition(uuid, uuid, uuid) is
  'Records that a couple added a flight. service_role only — a client that could call this could '
  'also decline to, which is the same as having no limit.';
