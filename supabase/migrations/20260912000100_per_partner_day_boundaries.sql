-- Each partner gets their own local-midnight day boundary.
--
-- Until now a couple shared one boundary: `private.couple_day` took `greatest()` of both partners'
-- local dates and midnights, so the couple effectively lived on the *ahead* partner's calendar. For
-- a London/Melbourne pair that put the daily-question reset and the streak deadline at 3pm London
-- time — which is the same complaint that started this work ("my streak resets at some random time
-- like 9:45pm"), just relocated rather than fixed. Nine hours apart, there is no shared midnight to
-- find; the only honest answer is to stop looking for one.
--
-- So `private.viewer_day()` now reports the caller's *own* timezone. London's day rolls at London
-- midnight, Melbourne's at Melbourne midnight.
--
-- This does not split the couple up. The daily question is still one shared session per calendar
-- date: each partner joins date D's session during their own date D, up to a day apart in wall
-- clock, and both answers land on the same row. `get_daily_question_session` already keys on
-- `daily_local_date = <viewer's date>`, so it needed no change beyond the new viewer_day.
--
-- What did need care is anything that previously assumed one boundary for two people:
--
--   * advance_game_session credited the streak to `couple_day`'s date. With per-partner dates the
--     responder's "today" is ambiguous, so it now credits the *session's* own `daily_local_date` —
--     the day both people were answering for, regardless of who finished second or when.
--   * get_daily_question_status compared against `couple_day`; it now uses viewer_day, so each
--     partner sees the status of the session for their own current day.
--   * Streak reminders fired once per couple at the shared boundary, which under per-partner days
--     would nudge one partner at the wrong time of night. They're now per-profile, which also means
--     the "already reminded" bookkeeping has to be per-profile — `daily_streaks`'
--     early/final_reminder_sent_date are per couple and can't express it.
--
-- `private.couple_day` and `public.list_couple_day_bounds` are left in place but unused, so the
-- currently-deployed send-streak-reminders keeps working until it's redeployed against the new
-- per-profile RPC below. They can be dropped once that's out.

-- 1. The viewer's own day.
create or replace function private.viewer_day(p_at timestamptz default now())
returns table(couple_id uuid, local_date date, next_boundary timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select
    (
      select c.id from public.couples c
      where (c.partner_a_id = auth.uid() or c.partner_b_id = auth.uid()) and c.status = 'active'
      limit 1
    ),
    private.local_date_at(p.timezone, p_at),
    private.next_local_midnight(p.timezone, p_at)
  from public.profiles p
  where p.id = auth.uid();
$$;

-- 2. Status of the session for the viewer's own day.
create or replace function public.get_daily_question_status()
returns table(session_id uuid, my_answered boolean, partner_answered boolean)
language sql
stable
security definer
set search_path = public
as $$
  select
    gs.id as session_id,
    coalesce(bool_or(gr.responder_id = auth.uid()), false) as my_answered,
    coalesce(bool_or(gr.responder_id <> auth.uid()), false) as partner_answered
  from public.game_sessions gs
  left join public.game_responses gr on gr.session_id = gs.id
  where gs.is_daily
    and public.is_couple_member(gs.couple_id)
    and gs.daily_local_date = (select local_date from private.viewer_day())
  group by gs.id;
$$;

-- 3. Streak credited to the session's day.
create or replace function public.advance_game_session()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_total_rounds int;
  v_couple_id uuid;
  v_initiator_id uuid;
  v_partner_a_id uuid;
  v_partner_b_id uuid;
  v_partner_a_count int;
  v_partner_b_count int;
  v_solo_count int;
  v_both_complete boolean;
  v_is_daily boolean;
  v_local_date date;
begin
  select total_rounds, couple_id, is_daily, initiator_id
  into v_total_rounds, v_couple_id, v_is_daily, v_initiator_id
  from public.game_sessions where id = new.session_id;

  if v_couple_id is null then
    select count(distinct round_number) into v_solo_count
    from public.game_responses
    where session_id = new.session_id and responder_id = v_initiator_id;

    v_both_complete := v_solo_count >= v_total_rounds;

    update public.game_sessions
    set started_at = coalesce(started_at, now()),
        updated_at = now(),
        status = (case when v_both_complete then 'completed' else 'active' end)::public.game_status,
        completed_at = case when v_both_complete then coalesce(completed_at, now()) else completed_at end
    where id = new.session_id;

    return new;
  end if;

  select partner_a_id, partner_b_id into v_partner_a_id, v_partner_b_id
  from public.couples where id = v_couple_id;

  select count(distinct round_number) into v_partner_a_count
  from public.game_responses
  where session_id = new.session_id and responder_id = v_partner_a_id;

  select count(distinct round_number) into v_partner_b_count
  from public.game_responses
  where session_id = new.session_id and responder_id = v_partner_b_id;

  v_both_complete := v_partner_a_count >= v_total_rounds and v_partner_b_count >= v_total_rounds;

  update public.game_sessions
  set started_at = coalesce(started_at, now()),
      updated_at = now(),
      status = (case when v_both_complete then 'completed' else 'active' end)::public.game_status,
      completed_at = case when v_both_complete then coalesce(completed_at, now()) else completed_at end
  where id = new.session_id;

  if v_is_daily and v_both_complete then
    -- The day the *session* belongs to, not whatever day either partner is currently in.
    -- With per-partner boundaries the two can disagree by up to a day, and crediting the
    -- streak to the responder's own "today" would let the same session bump two different
    -- dates depending on who finished it second. The session's date is the one both people
    -- were answering for.
    select daily_local_date into v_local_date
    from public.game_sessions where id = new.session_id;

    insert into public.daily_streaks (couple_id, current_streak, longest_streak, last_answered_date, updated_at)
    values (v_couple_id, 1, 1, v_local_date, now())
    on conflict (couple_id) do update set
      current_streak = case
        when public.daily_streaks.last_answered_date = v_local_date then public.daily_streaks.current_streak
        when public.daily_streaks.last_answered_date = v_local_date - 1 then public.daily_streaks.current_streak + 1
        else 1
      end,
      longest_streak = greatest(
        public.daily_streaks.longest_streak,
        case
          when public.daily_streaks.last_answered_date = v_local_date then public.daily_streaks.current_streak
          when public.daily_streaks.last_answered_date = v_local_date - 1 then public.daily_streaks.current_streak + 1
          else 1
        end
      ),
      last_answered_date = v_local_date,
      updated_at = now();
  end if;

  return new;
end;
$function$;

-- 4. Per-profile reminder bookkeeping.
--
-- `daily_streaks.early_reminder_sent_date`/`final_reminder_sent_date` are per couple, which was
-- fine when both partners were reminded at the same instant. Now that each is reminded at their own
-- local boundary, one partner's send would suppress the other's. Those two columns are left alone
-- (the deprecated list_couple_day_bounds still reads them) and superseded by this.
create table if not exists public.streak_reminder_sends (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  reminder_kind text not null check (reminder_kind in ('early', 'final')),
  sent_for_date date not null,
  updated_at timestamptz not null default now(),
  primary key (profile_id, reminder_kind)
);

-- No policies: only send-streak-reminders touches this, and it holds the service role, which
-- bypasses RLS. Enabling RLS with no policy is what keeps it unreadable by app users.
alter table public.streak_reminder_sends enable row level security;

-- One row per person per active couple, each with their own boundary.
create or replace function public.list_streak_reminder_targets()
returns table (
  profile_id uuid,
  couple_id uuid,
  partner_id uuid,
  local_date date,
  next_boundary timestamptz,
  current_streak int,
  early_reminder_sent_date date,
  final_reminder_sent_date date
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    c.id,
    case when c.partner_a_id = p.id then c.partner_b_id else c.partner_a_id end,
    private.local_date_at(p.timezone, now()),
    private.next_local_midnight(p.timezone, now()),
    coalesce(ds.current_streak, 0)::int,
    early.sent_for_date,
    final.sent_for_date
  from public.couples c
  join public.profiles p on p.id in (c.partner_a_id, c.partner_b_id)
  left join public.daily_streaks ds on ds.couple_id = c.id
  left join public.streak_reminder_sends early
    on early.profile_id = p.id and early.reminder_kind = 'early'
  left join public.streak_reminder_sends final
    on final.profile_id = p.id and final.reminder_kind = 'final'
  where c.status = 'active';
$$;

-- Service role only, same as list_couple_day_bounds — this enumerates every couple in the app, so
-- an app user must never be able to call it.
revoke all on function public.list_streak_reminder_targets() from public;
grant execute on function public.list_streak_reminder_targets() to service_role;
