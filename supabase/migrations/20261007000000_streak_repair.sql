-- ---------------------------------------------------------------------------
-- Repairing a streak that broke yesterday
-- ---------------------------------------------------------------------------
--
-- A one-off purchase that bridges a single missed day, available only while the miss is recent.
--
-- Nothing here reconstructs anything, because nothing was destroyed. A broken streak is not zeroed
-- in storage: `daily_streaks.current_streak` keeps its number and `get_daily_streak` simply stops
-- reporting it once `last_answered_date` falls behind the couple's local yesterday. What actually
-- ends a streak is the *next* answer landing on a date more than one day after the last, which
-- sends the trigger down its `else 1` branch.
--
-- So a repair moves `last_answered_date` forward to yesterday. The stored streak becomes visible
-- again, and answering today continues it rather than restarting it. It deliberately does not
-- insert a game session for the day that was missed — the couple did miss it, and their history
-- should keep saying so.
--
-- ---------------------------------------------------------------------------
-- When it is offered
-- ---------------------------------------------------------------------------
--
-- Exactly when the last answered date is the day before yesterday, in the couple's own local
-- reckoning (`private.couple_day`, which takes the later of the two partners' midnights).
--
--   last answered = yesterday        nothing is broken; today is still available
--   last answered = day before that  broken when yesterday ended — at most 24 hours ago
--   last answered = earlier          two or more days missed; outside the window, not offered
--
-- That is what "within the past 24 hours" means here: the break happens at a local midnight, so
-- the window is the day that follows it.
--
-- ---------------------------------------------------------------------------
-- The purchase is not the client's word
-- ---------------------------------------------------------------------------
--
-- A repair needs a credit, and credits are written only by the RevenueCat webhook, as service_role
-- — the same rule the subscription columns follow, for the same reason. If the app could grant its
-- own credit then the purchase would be advisory, and this is a paid product.
--
-- Keyed on the store's transaction id, uniquely, so RevenueCat redelivering a NON_RENEWING_PURCHASE
-- event grants one credit rather than several. Redelivery is normal, not exceptional.

create table public.streak_repair_credits (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  -- The store's own transaction id. Unique, which is what makes granting idempotent.
  transaction_id text not null unique,
  granted_at timestamptz not null default now(),
  consumed_at timestamptz,
  consumed_for_couple_id uuid references public.couples (id) on delete set null
);

create index streak_repair_credits_unconsumed_idx
  on public.streak_repair_credits (profile_id) where consumed_at is null;

alter table public.streak_repair_credits enable row level security;

-- Readable by the person who bought it, so the app can show what they hold. No insert, update or
-- delete policy: a client that could write this could repair for free.
create policy "streak_repair_credits_select_own" on public.streak_repair_credits
  for select using (profile_id = auth.uid());

comment on table public.streak_repair_credits is
  'One purchased streak repair. Written only by the revenuecat-webhook function; consumed by '
  'public.repair_couple_streak.';

-- ---------------------------------------------------------------------------
-- Granting, from the webhook
-- ---------------------------------------------------------------------------

create or replace function private.grant_streak_repair_credit(
  p_profile_id uuid,
  p_transaction_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.streak_repair_credits (profile_id, transaction_id)
  values (p_profile_id, p_transaction_id)
  on conflict (transaction_id) do nothing;

  -- False means this transaction had already been granted — a redelivery, which is success.
  return found;
end;
$$;

revoke all on function private.grant_streak_repair_credit(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- What the app needs to decide whether to offer it
-- ---------------------------------------------------------------------------

create or replace function public.streak_repair_state()
returns table (
  repairable boolean,
  streak_at_risk integer,
  credits integer,
  missed_date date
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_couple_id uuid;
  v_today date;
  v_streak public.daily_streaks;
  v_credits integer;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select count(*)::integer into v_credits
  from public.streak_repair_credits
  where profile_id = v_me and consumed_at is null;

  select id into v_couple_id
  from public.couples
  where status = 'active' and (partner_a_id = v_me or partner_b_id = v_me);

  if v_couple_id is null then
    return query select false, 0, v_credits, null::date;
    return;
  end if;

  select local_date into v_today from private.couple_day(v_couple_id);
  select * into v_streak from public.daily_streaks where couple_id = v_couple_id;

  if not found or v_streak.last_answered_date is null or v_streak.current_streak <= 0 then
    return query select false, 0, v_credits, null::date;
    return;
  end if;

  -- The window, and nothing else. A streak still alive has nothing to repair; one that lapsed
  -- more than a day ago is past offering.
  if v_streak.last_answered_date <> v_today - 2 then
    return query select false, 0, v_credits, null::date;
    return;
  end if;

  return query select true, v_streak.current_streak, v_credits, v_today - 1;
end;
$$;

revoke all on function public.streak_repair_state() from public;
grant execute on function public.streak_repair_state() to authenticated;

-- ---------------------------------------------------------------------------
-- The repair
-- ---------------------------------------------------------------------------

create or replace function public.repair_couple_streak()
returns table (repaired boolean, current_streak integer, error_message text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_couple_id uuid;
  v_today date;
  v_streak public.daily_streaks;
  v_credit_id uuid;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select id into v_couple_id
  from public.couples
  where status = 'active' and (partner_a_id = v_me or partner_b_id = v_me);

  if v_couple_id is null then
    return query select false, 0, 'You need a partner before you have a streak to repair.'::text;
    return;
  end if;

  -- Locked for the duration. Both partners can hold credits and both can be looking at the same
  -- offer, and two repairs of one missed day must not spend two of them.
  select * into v_streak from public.daily_streaks where couple_id = v_couple_id for update;
  select local_date into v_today from private.couple_day(v_couple_id);

  if not found or v_streak.last_answered_date is null or v_streak.current_streak <= 0 then
    return query select false, 0, 'There''s no streak to repair.'::text;
    return;
  end if;

  if v_streak.last_answered_date = v_today or v_streak.last_answered_date = v_today - 1 then
    return query select false, v_streak.current_streak, 'Your streak is still going.'::text;
    return;
  end if;

  if v_streak.last_answered_date < v_today - 2 then
    return query select false, 0, 'This streak has been broken for too long to repair.'::text;
    return;
  end if;

  -- Oldest first, so someone holding several spends the one they bought longest ago. `skip locked`
  -- because two simultaneous repairs must take different rows rather than queue for the same one.
  select id into v_credit_id
  from public.streak_repair_credits
  where profile_id = v_me and consumed_at is null
  order by granted_at
  limit 1
  for update skip locked;

  if v_credit_id is null then
    return query select false, v_streak.current_streak, 'no_credit'::text;
    return;
  end if;

  update public.streak_repair_credits
  set consumed_at = now(), consumed_for_couple_id = v_couple_id
  where id = v_credit_id;

  -- Yesterday, not today. Bridging the gap is the whole repair: the stored streak becomes visible
  -- again and today's answer continues it. Writing today instead would credit them with an answer
  -- they have not given yet, and the trigger would then decline to count the real one.
  update public.daily_streaks
  set last_answered_date = v_today - 1, updated_at = now()
  where couple_id = v_couple_id;

  return query select true, v_streak.current_streak, null::text;
end;
$$;

revoke all on function public.repair_couple_streak() from public;
grant execute on function public.repair_couple_streak() to authenticated;

comment on function public.repair_couple_streak() is
  'Spends one purchased credit to bridge a single missed day. Refuses without a credit — '
  '''no_credit'' is returned rather than raised so the app can offer the purchase.';
