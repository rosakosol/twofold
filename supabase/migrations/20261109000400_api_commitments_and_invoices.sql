-- ---------------------------------------------------------------------------
-- What we are committed to pay, and what we were actually charged
-- ---------------------------------------------------------------------------
--
-- AeroAPI carries a USD 100 monthly minimum. That single fact changes what this whole schema is
-- measuring.
--
-- What we pay is `max(minimum, discounted usage)`. On the invoice 20261109000200 is built from,
-- discounted usage was $0.41 against $4.93 of list — and even reading that invoice as a single
-- day, which the call counts suggest it is (345 calls to /flights/{ident}, against the 291/24h
-- recorded in refresh-due-flights' own header), a month of it is about $12.50 discounted. Well
-- under the floor.
--
-- So every AeroAPI call currently made is already paid for. Deduping the refresh loop saves
-- nothing. Lengthening the delay-stats cache saves nothing. Those are headroom changes — they
-- raise how far the app can grow inside the hundred dollars — and they should be argued for on
-- that basis rather than as savings, because as savings they are worth exactly zero.
--
-- ---------------------------------------------------------------------------
-- Which means a spend alert would be blind
-- ---------------------------------------------------------------------------
--
-- The failure this metering exists to catch — a cadence constant that quietly triples call volume,
-- as the 2-minute mid-cruise tier did — costs nothing under the floor and shows nothing on the
-- invoice. A threshold in dollars would never fire. The signal has to be relative: this week
-- against last, calls per tracked flight, a day that does not look like the days before it.
--
-- That is what these tables are for. `api_usage_daily` says what happened; these say what it was
-- supposed to cost and what it actually cost, and the gap between those two is the only way to
-- learn a discount curve the vendor does not publish.
--
-- ---------------------------------------------------------------------------
-- The discount is observed, never assumed
-- ---------------------------------------------------------------------------
--
-- FlightAware applies volume discounts and does not document the curve anywhere we can find. So it
-- is not modelled: `api_invoices` records what each month was actually charged next to what this
-- database computed at list, and the ratio between them is measured rather than guessed. After a
-- few months that ratio IS the curve, discovered from our own invoices, and the point at which
-- growth would carry us past the floor becomes something observed rather than something predicted
-- from a number nobody has.

create table if not exists private.api_commitments (
  provider text not null,
  -- The floor. `max(this, discounted usage)` is the bill.
  monthly_minimum_usd numeric(12, 2) not null check (monthly_minimum_usd >= 0),
  effective_from date not null,
  note text,
  primary key (provider, effective_from)
);

comment on table private.api_commitments is
  'Contractual monthly minimums. Below the minimum, usage is already paid for and call-count '
  'reductions save nothing — which is why the console shows utilisation against this rather than '
  'spend, and why alerting is on relative change rather than dollars.';

insert into private.api_commitments (provider, monthly_minimum_usd, effective_from, note) values
  ('aeroapi', 100.00, date '2026-01-01',
    'USD 100/month minimum. Volume discounts exist above it; FlightAware does not publish the '
    'curve, so it is observed via api_invoices rather than modelled.')
on conflict (provider, effective_from) do update set
  monthly_minimum_usd = excluded.monthly_minimum_usd,
  note = excluded.note;

-- ---------------------------------------------------------------------------
-- The invoices themselves
-- ---------------------------------------------------------------------------
--
-- Entered by hand, because there is no API that returns them. Two figures per month, both off the
-- vendor's own statement: what it would have cost at list, and what was actually charged.
--
-- `list_total_usd` is what makes this more than a record. Compared against what `api_usage_daily`
-- independently computed for the same month, it says whether our metering is counting the right
-- things at all — a widening gap means we are mismodelling something, and that is a bug in this
-- schema rather than a surprise from the vendor.

create table if not exists private.api_invoices (
  provider text not null,
  -- The first of the billing month.
  billing_month date not null,
  -- The vendor's own pre-discount total, where the statement shows one. Compared against our
  -- computed list cost to check the metering itself.
  list_total_usd numeric(12, 2),
  -- What was actually charged, after discounts and after any minimum was applied.
  charged_usd numeric(12, 2) not null check (charged_usd >= 0),
  note text,
  recorded_at timestamptz not null default now(),
  primary key (provider, billing_month),
  constraint api_invoices_month_is_first check (billing_month = date_trunc('month', billing_month)::date)
);

comment on table private.api_invoices is
  'Vendor invoices, entered by hand. charged_usd against our own computed list cost is how the '
  'unpublished volume-discount curve becomes measurable; list_total_usd against it is how a bug '
  'in our metering becomes visible.';

-- The commitment in force for a provider on a given day.
create or replace function private.api_minimum_on(p_provider text, p_day date)
returns numeric
language sql
stable
set search_path = private, public
as $$
  select monthly_minimum_usd
  from private.api_commitments
  where provider = p_provider
    and effective_from <= p_day
  order by effective_from desc
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- Where this month stands
-- ---------------------------------------------------------------------------
--
-- The console's headline read. Deliberately reports utilisation of the floor rather than spend,
-- because spend is a constant until the floor is crossed and utilisation is the number that
-- actually moves.

create or replace function private.api_month_to_date(
  p_provider text default 'aeroapi',
  p_month date default date_trunc('month', current_date)::date
)
returns table (
  billing_month date,
  list_cost_usd numeric,
  calls bigint,
  billable_calls bigint,
  monthly_minimum_usd numeric,
  -- List cost as a percentage of the floor. Over 100 does NOT mean over the floor — the discount
  -- sits between them — but it is the point at which the floor stops being a safe assumption.
  list_utilisation_percent numeric,
  -- Straight-line from completed days only. Null on the first of the month, when there is no
  -- completed day to extrapolate from; a partial day would project a number that is wrong in a
  -- direction nobody could reason about.
  projected_list_usd numeric,
  -- charged / our computed list, averaged over every invoice recorded. The discount curve, as far
  -- as it has been observed. Null until an invoice has been entered.
  observed_discount_ratio numeric
)
language sql
stable
security definer
set search_path = private, public
as $$
  with bounds as (
    select
      date_trunc('month', p_month)::date as month_start,
      (date_trunc('month', p_month) + interval '1 month')::date as next_month
  ),
  usage as (
    select
      coalesce(sum(d.estimated_cost_usd), 0)::numeric as list_cost,
      coalesce(sum(d.calls), 0)::bigint as calls,
      coalesce(sum(d.billable_calls), 0)::bigint as billable
    from private.api_usage_daily d, bounds b
    where d.provider = p_provider
      and d.day >= b.month_start
      and d.day < b.next_month
  ),
  elapsed as (
    select
      -- Completed days in the month so far. For a month already past, the whole month.
      case
        when b.next_month <= current_date then (b.next_month - b.month_start)
        else greatest(current_date - b.month_start, 0)
      end as completed_days,
      (b.next_month - b.month_start) as days_in_month
    from bounds b
  ),
  discount as (
    select avg(
      case when computed.list_cost > 0 then i.charged_usd / computed.list_cost end
    ) as ratio
    from private.api_invoices i
    cross join lateral (
      select coalesce(sum(d.estimated_cost_usd), 0)::numeric as list_cost
      from private.api_usage_daily d
      where d.provider = i.provider
        and d.day >= i.billing_month
        and d.day < (i.billing_month + interval '1 month')::date
    ) computed
    where i.provider = p_provider
  )
  select
    b.month_start,
    u.list_cost,
    u.calls,
    u.billable,
    private.api_minimum_on(p_provider, b.month_start),
    case
      when private.api_minimum_on(p_provider, b.month_start) > 0
        then round(u.list_cost / private.api_minimum_on(p_provider, b.month_start) * 100, 2)
    end,
    case
      when e.completed_days > 0
        then round(u.list_cost / e.completed_days * e.days_in_month, 6)
    end,
    round(d.ratio, 6)
  from bounds b, usage u, elapsed e, discount d;
$$;

revoke all on function private.api_month_to_date(text, date) from public, anon, authenticated;
revoke all on function private.api_minimum_on(text, date) from public, anon, authenticated;
