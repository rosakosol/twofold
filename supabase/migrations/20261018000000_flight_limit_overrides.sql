-- ---------------------------------------------------------------------------
-- Per-account flight tracking overrides
-- ---------------------------------------------------------------------------
--
-- One admin/development account needs to track flights without the monthly cap getting in the way,
-- which the tier table cannot express: `flight_limit_for_tier` maps a tier to a number, and the
-- account in question is on a tier that other people share.
--
-- So the override is keyed on the profile instead, and sits *beside* the tier rule rather than
-- replacing it: with no row here, nothing about the allowance changes for anybody.
--
-- ---------------------------------------------------------------------------
-- Why `private`
-- ---------------------------------------------------------------------------
--
-- This table decides how much AeroAPI money an account may spend, so a client that could write it
-- could grant itself an unlimited bill. `config.toml` serves `public` and `graphql_public` only, so
-- a table in `private` is unreachable over PostgREST entirely — no grant to get wrong, no RLS
-- policy to get subtly wrong, and nothing to remember when a future migration adds a policy
-- elsewhere. Same reasoning `private.couple_effective_tier` is where it is.
--
-- It is deliberately *not* a column on `profiles`. That table is client-readable, and the
-- subscription columns on it already needed a trigger to stop clients writing them
-- (20260915000000) — adding a second column with the same requirement means a second thing
-- depending on that trigger staying correct.
--
-- ---------------------------------------------------------------------------
-- Scope
-- ---------------------------------------------------------------------------
--
-- The allowance is a couple's, not a person's — one subscription covers both partners and they
-- draw on one pool. So an override held by either partner raises the pool for that couple, which
-- is what shared means. It raises nothing else: this is the flight cap and not a tier, so an
-- override grants no premium decks, no Hard sudoku, no chess.

create table if not exists private.flight_limit_overrides (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  -- `>= 0` rather than `> 0` so an override can also be used to freeze an account's tracking
  -- outright, which is the same mechanism pointed the other way.
  monthly_limit integer not null check (monthly_limit >= 0),
  -- Why this row exists. Not decoration: an unexplained override found in two years' time is
  -- indistinguishable from a mistake, and nobody will dare delete it.
  note text,
  created_at timestamptz not null default now()
);

comment on table private.flight_limit_overrides is
  'Per-account monthly live-tracking allowances that replace the tier default. In `private` '
  'because it authorises spend: it is unreachable over PostgREST, so no client can write itself '
  'an unlimited AeroAPI bill. An override held by either partner applies to their couple.';

-- The allowance, override first, tier second. Both call sites go through this now so the two
-- cannot disagree — the previous arrangement had each of them call `flight_limit_for_tier`
-- separately, which is exactly how one of them ends up missing a rule the other has.
create or replace function private.flight_limit_for_couple(p_couple_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    -- `max`, so that if both partners somehow hold an override the couple gets the larger. There
    -- is no sensible reading in which having two of them is worse than having one.
    (
      select max(o.monthly_limit)
      from private.flight_limit_overrides o
      join public.couples c on c.id = p_couple_id
      where o.profile_id in (c.partner_a_id, c.partner_b_id)
    ),
    public.flight_limit_for_tier(private.couple_effective_tier(p_couple_id))
  );
$$;

comment on function private.flight_limit_for_couple(uuid) is
  'This couple''s monthly live-tracking allowance: an override held by either partner if there is '
  'one, otherwise the tier default. The single source both `flight_allowance` and '
  '`enable_flight_tracking` read.';

-- ---------------------------------------------------------------------------
-- The two call sites
-- ---------------------------------------------------------------------------
--
-- Both are replaced whole because `create or replace function` has no way to change one line.
-- Everything except the allowance lookup is carried across unchanged from 20260930000000 and
-- 20261010000400 respectively.

create or replace function public.flight_allowance(p_couple_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_couple_member(p_couple_id) then
    raise exception 'not a member of this couple' using errcode = '42501';
  end if;

  -- Still reports the real tier. The override changes what the couple may spend, not who they
  -- are, and a screen that renamed their plan because of it would be lying about the subscription.
  return jsonb_build_object(
    'tier', private.couple_effective_tier(p_couple_id),
    'limit', private.flight_limit_for_couple(p_couple_id),
    'used', public.flights_used_this_month(p_couple_id)
  );
end;
$$;

comment on function public.flight_allowance(uuid) is
  'This couple''s monthly flight allowance and how much of it is spent. Membership-checked, so it '
  'is safe to expose to the client — the tier itself comes from a schema PostgREST does not serve.';

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
  'added without it. Membership-checked. A flight spends at most one slot ever, and a flight that '
  'has already arrived spends none.';

-- ---------------------------------------------------------------------------
-- The account itself
-- ---------------------------------------------------------------------------
--
-- Matched on `auth.users.email` rather than a hardcoded uuid, so this migration says who it is
-- about in a form a person can read and check.
--
-- `select ... from auth.users` inserts nothing when that account does not exist, which is the
-- right behaviour on a fresh local database or a branch: the override is for one real account, and
-- a migration that failed without it would block everyone else's `db reset`.
insert into private.flight_limit_overrides (profile_id, monthly_limit, note)
select p.id, 100000, 'Admin account — effectively uncapped for testing and support.'
from public.profiles p
join auth.users u on u.id = p.id
where lower(u.email) = 'kosolrosa@gmail.com'
on conflict (profile_id) do update
  set monthly_limit = excluded.monthly_limit,
      note = excluded.note;
