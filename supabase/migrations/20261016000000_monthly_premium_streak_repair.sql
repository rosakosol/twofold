-- ---------------------------------------------------------------------------
-- One streak repair a month, included with Premium
-- ---------------------------------------------------------------------------
--
-- Reuses the machinery that already exists rather than building a parallel one. A repair is a row
-- in `streak_repair_credits`, and `repair_couple_streak` already spends one and bridges the missed
-- day. The only thing missing was a way to get a credit without paying for it.
--
-- ---------------------------------------------------------------------------
-- One a month, per couple — not per person
-- ---------------------------------------------------------------------------
--
-- The plan this comes from keyed the monthly credit on `profile_id`, which would have given a
-- couple two free repairs a month: one each, for a streak they share. The streak is the couple's,
-- so the allowance is the couple's. The synthetic `transaction_id` is therefore
-- `premium-monthly:<couple_id>:<YYYY-MM>`, and the table's existing unique index on that column
-- enforces the whole rule by itself — no counter, no cron, no new state to keep in step.
--
-- The month is the couple's own local month, from `private.couple_day`, which is the same boundary
-- the streak itself uses. A freeze that became available at UTC midnight would arrive on the wrong
-- day for most of the world, and this is a feature about days.
--
-- ---------------------------------------------------------------------------
-- Granted and spent in one call
-- ---------------------------------------------------------------------------
--
-- The plan had the client claim a credit and then spend it. Two steps leave a dangling free credit
-- whenever the second one fails — and worse, that credit belongs to whichever partner claimed it,
-- so the other one would be told there is no repair available while the couple's monthly freeze
-- sat unused on an account they cannot see.
--
-- Doing both in one transaction removes that state entirely. If the repair cannot go ahead, nothing
-- is granted and nothing is spent.

-- One spelling of the key, used by the check above and the claim below. Two copies of a string that
-- decides whether somebody gets something free is one copy too many.
create or replace function private.monthly_freeze_transaction_id(p_couple_id uuid, p_local_date date)
returns text
language sql
immutable
as $$
  select 'premium-monthly:' || p_couple_id::text || ':' || to_char(p_local_date, 'YYYY-MM');
$$;

revoke all on function private.monthly_freeze_transaction_id(uuid, date) from public, anon, authenticated;

-- The signature gains a column, which `create or replace` cannot do to a `returns table`.
drop function if exists public.streak_repair_state();

create or replace function public.streak_repair_state()
returns table (
  repairable boolean,
  streak_at_risk integer,
  credits integer,
  missed_date date,
  -- Whether this couple's included repair is still unspent this month. False for anyone not on
  -- Premium, which is what lets the card offer the paywall instead of a button that would refuse.
  monthly_freeze_available boolean
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
  v_freeze boolean := false;
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
    return query select false, 0, v_credits, null::date, false;
    return;
  end if;

  select local_date into v_today from private.couple_day(v_couple_id);

  if private.couple_effective_tier(v_couple_id) = 'premium' then
    v_freeze := not exists (
      select 1 from public.streak_repair_credits
      where transaction_id = private.monthly_freeze_transaction_id(v_couple_id, v_today)
    );
  end if;

  select * into v_streak from public.daily_streaks where couple_id = v_couple_id;

  if not found or v_streak.last_answered_date is null or v_streak.current_streak <= 0 then
    return query select false, 0, v_credits, null::date, v_freeze;
    return;
  end if;

  -- The window, and nothing else. A streak still alive has nothing to repair; one that lapsed more
  -- than a day ago is past offering.
  if v_streak.last_answered_date <> v_today - 2 then
    return query select false, 0, v_credits, null::date, v_freeze;
    return;
  end if;

  return query select true, v_streak.current_streak, v_credits, v_today - 1, v_freeze;
end;
$$;

revoke all on function public.streak_repair_state() from public;
grant execute on function public.streak_repair_state() to authenticated;

-- ---------------------------------------------------------------------------
-- Using it
-- ---------------------------------------------------------------------------
--
-- Deliberately separate from `repair_couple_streak` rather than folded into it. That one spends
-- something the person bought, and this one spends something their plan includes; a single function
-- that silently picked would make "which did I just use" unanswerable, and the screen offers them
-- as two different things because they are.
create or replace function public.repair_streak_with_monthly_freeze()
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
  v_transaction text;
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

  if private.couple_effective_tier(v_couple_id) is distinct from 'premium' then
    return query select false, 0, 'premium_required'::text;
    return;
  end if;

  -- Locked for the duration, like the paid repair: both partners can be looking at the same offer,
  -- and two repairs of one missed day must not spend two things.
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

  -- The grant and the spend, in one transaction. A conflict here means this couple has already used
  -- this month's repair — by either of them, which is the point of keying it on the couple.
  v_transaction := private.monthly_freeze_transaction_id(v_couple_id, v_today);

  insert into public.streak_repair_credits (profile_id, transaction_id)
  values (v_me, v_transaction)
  on conflict (transaction_id) do nothing
  returning id into v_credit_id;

  if v_credit_id is null then
    return query select false, v_streak.current_streak, 'freeze_used'::text;
    return;
  end if;

  update public.streak_repair_credits
  set consumed_at = now(), consumed_for_couple_id = v_couple_id
  where id = v_credit_id;

  -- Yesterday, not today — the same bridge the paid repair makes, for the same reason: writing
  -- today would credit them with an answer they have not given, and the trigger would then decline
  -- to count the real one.
  update public.daily_streaks
  set last_answered_date = v_today - 1, updated_at = now()
  where couple_id = v_couple_id;

  return query select true, v_streak.current_streak, null::text;
end;
$$;

revoke all on function public.repair_streak_with_monthly_freeze() from public, anon;
grant execute on function public.repair_streak_with_monthly_freeze() to authenticated;

comment on function public.repair_streak_with_monthly_freeze() is
  'Spends the couple''s included monthly repair and bridges the missed day. Grants and consumes the '
  'credit in one transaction, so a repair that cannot go ahead leaves nothing spent. One per couple '
  'per local month, enforced by the unique index on streak_repair_credits.transaction_id.';
