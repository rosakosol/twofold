-- ---------------------------------------------------------------------------
-- The console's way in to the usage tables
-- ---------------------------------------------------------------------------
--
-- Everything in 20261109000100 through 000400 lives in `private`, which `config.toml` does not
-- serve over PostgREST at any privilege level. That is what makes those tables safe, and it also
-- means the console cannot read a single row of them. This is the door: security-definer functions
-- in `public`, each of which checks `is_billing_admin()` on entry and returns exactly the shape one
-- screen needs.
--
-- Not broadened access to the tables themselves. A grant would put the whole of `api_usage_events`
-- — every flight, every couple, every call — one PostgREST query away from any signed-in client if
-- a policy were ever got wrong. The blast radius of a function is its body.
--
-- ---------------------------------------------------------------------------
-- And a gate the console itself was missing
-- ---------------------------------------------------------------------------
--
-- The console's layout gates on `is_feedback_admin()`, which since 20261109000000 means the
-- `content` role specifically. A billing-only admin — the whole point of that role being separate,
-- so that seeing what the app costs does not require being trusted with anybody's account — could
-- not reach the console at all, and would be redirected to the public feedback board.
--
-- So `is_console_admin()`: holds any role at all. The layout uses it to decide who gets through
-- the front door; each page still checks the role it actually needs. That is the right way round.
-- The other way, a page added to the console is readable by every admin until somebody remembers
-- to narrow it.

create or replace function public.is_console_admin(check_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.feedback_admins where profile_id = check_id);
$$;

comment on function public.is_console_admin(uuid) is
  'Holds any admin role. Gates entry to the console shell only — every page inside still checks '
  'the specific role it needs (is_feedback_admin for content, is_billing_admin for spend, '
  'is_support_admin for accounts).';

grant execute on function public.is_console_admin(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Where this month stands
-- ---------------------------------------------------------------------------
--
-- Reports utilisation of the monthly minimum rather than spend, because below the floor spend is a
-- constant and utilisation is the only figure that moves. See 20261109000400.

create or replace function public.api_usage_summary(
  p_provider text default 'aeroapi',
  p_month date default date_trunc('month', current_date)::date
)
returns table (
  billing_month date,
  list_cost_usd numeric,
  calls bigint,
  billable_calls bigint,
  monthly_minimum_usd numeric,
  list_utilisation_percent numeric,
  projected_list_usd numeric,
  observed_discount_ratio numeric
)
language plpgsql
stable
security definer
set search_path = private, public
as $$
begin
  if not public.is_billing_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  return query select * from private.api_month_to_date(p_provider, p_month);
end;
$$;

-- ---------------------------------------------------------------------------
-- What each endpoint cost, and how much of it was wasted
-- ---------------------------------------------------------------------------
--
-- `calls` against `distinct_upstream` is the duplicate-fetch measurement: `refresh-due-flights`'s
-- main loop is not deduped by fa_flight_id (only `syncLivePositions` is, and that pass hits the
-- free ADS-B mirrors), so two couples tracking one real-world flight bill two identical calls per
-- tick. The ratio between those two columns is what a decision to fix that should rest on.

create or replace function public.api_usage_by_endpoint(
  p_provider text default 'aeroapi',
  p_from date default (current_date - 29),
  p_to date default current_date
)
returns table (
  endpoint text,
  calls bigint,
  billable_calls bigint,
  errors bigint,
  retries bigint,
  distinct_upstream bigint,
  list_cost_usd numeric,
  unit_price_usd numeric
)
language plpgsql
stable
security definer
set search_path = private, public
as $$
begin
  if not public.is_billing_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  return query
    select
      d.endpoint,
      sum(d.calls)::bigint,
      sum(coalesce(d.billable_calls, 0))::bigint,
      sum(d.errors)::bigint,
      sum(d.retries)::bigint,
      -- Summed across days rather than counted across the window. `api_usage_daily` already
      -- collapsed each day's distinct flights, and the raw events behind them are purged at 60
      -- days, so a true window-wide distinct is not available from this table. A flight tracked
      -- across two days counts twice here — which is the right unit anyway, since it was polled on
      -- both of them.
      sum(coalesce(d.distinct_upstream, 0))::bigint,
      -- Null-preserving: an endpoint with no rate must not read as free just because another
      -- endpoint in the same window had one. `sum` ignores nulls, so the null is reasserted.
      case when bool_and(d.estimated_cost_usd is not null) then sum(d.estimated_cost_usd) end,
      private.api_rate_on(p_provider, d.endpoint, p_to)
    from private.api_usage_daily d
    where d.provider = p_provider
      and d.day >= p_from
      and d.day <= p_to
    group by d.endpoint
    order by sum(d.estimated_cost_usd) desc nulls last, sum(d.calls) desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- Day by day
-- ---------------------------------------------------------------------------
--
-- For the trend. The signal worth watching here is not the dollar figure — under the floor that is
-- a constant — but the shape: a step change in calls is how a cadence bug looks from the outside,
-- and it costs nothing, so nothing else would report it.

create or replace function public.api_usage_daily_series(
  p_provider text default 'aeroapi',
  p_from date default (current_date - 29),
  p_to date default current_date
)
returns table (
  day date,
  calls bigint,
  billable_calls bigint,
  errors bigint,
  distinct_upstream bigint,
  list_cost_usd numeric
)
language plpgsql
stable
security definer
set search_path = private, public
as $$
begin
  if not public.is_billing_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  return query
    select
      d.day,
      sum(d.calls)::bigint,
      sum(coalesce(d.billable_calls, 0))::bigint,
      sum(d.errors)::bigint,
      sum(coalesce(d.distinct_upstream, 0))::bigint,
      case when bool_and(d.estimated_cost_usd is not null) then sum(d.estimated_cost_usd) end
    from private.api_usage_daily d
    where d.provider = p_provider
      and d.day >= p_from
      and d.day <= p_to
    group by d.day
    order by d.day;
end;
$$;

-- The gate is inside each function, so `authenticated` may call them and a non-admin gets 42501.
-- Revoked from anon: there is no signed-out reader of any of this, and a function reachable
-- without a session is one more thing whose gate has to be right forever.
revoke execute on function public.api_usage_summary(text, date) from anon;
revoke execute on function public.api_usage_by_endpoint(text, date, date) from anon;
revoke execute on function public.api_usage_daily_series(text, date, date) from anon;

grant execute on function public.api_usage_summary(text, date) to authenticated;
grant execute on function public.api_usage_by_endpoint(text, date, date) to authenticated;
grant execute on function public.api_usage_daily_series(text, date, date) to authenticated;
