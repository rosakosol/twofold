-- The daily-question/streak reset boundary was a single shared UTC midnight for every couple —
-- a couple who connected mid-day got an arbitrary partial first "day" (as little as a few
-- minutes) before their very first daily question could reset, rather than a real full first
-- day together. Moves the boundary to be relative to each couple's own `couples.created_at`
-- (the exact moment `redeem_invite_code` paired them — `couples` rows can't exist with only one
-- partner known, both partner_a_id/partner_b_id are not null, so created_at really is "when they
-- connected") instead of a shared calendar date.

alter table public.daily_streaks
  add column last_answered_day_index int;

-- Backfill: best-effort reconstruction of each existing streak's day-index from its old
-- calendar-date value, relative to that couple's own created_at, so an already-active streak
-- doesn't just reset to 0 the moment this migration lands.
update public.daily_streaks ds
set last_answered_day_index = floor(
  extract(epoch from (ds.last_answered_date::timestamptz - c.created_at)) / 86400
)::int
from public.couples c
where c.id = ds.couple_id and ds.last_answered_date is not null;

alter table public.daily_streaks
  drop column last_answered_date;

create or replace function public.advance_game_session()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_rounds int;
  v_couple_id uuid;
  v_partner_a_id uuid;
  v_partner_b_id uuid;
  v_partner_a_count int;
  v_partner_b_count int;
  v_both_complete boolean;
  v_is_daily boolean;
  v_couple_created_at timestamptz;
  v_day_index int;
begin
  select total_rounds, couple_id, is_daily into v_total_rounds, v_couple_id, v_is_daily
  from public.game_sessions where id = new.session_id;

  select partner_a_id, partner_b_id, created_at into v_partner_a_id, v_partner_b_id, v_couple_created_at
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

  if v_is_daily then
    v_day_index := floor(extract(epoch from (now() - v_couple_created_at)) / 86400)::int;

    insert into public.daily_streaks (couple_id, current_streak, longest_streak, last_answered_day_index, updated_at)
    values (v_couple_id, 1, 1, v_day_index, now())
    on conflict (couple_id) do update set
      current_streak = case
        when public.daily_streaks.last_answered_day_index = v_day_index then public.daily_streaks.current_streak
        when public.daily_streaks.last_answered_day_index = v_day_index - 1 then public.daily_streaks.current_streak + 1
        else 1
      end,
      longest_streak = greatest(
        public.daily_streaks.longest_streak,
        case
          when public.daily_streaks.last_answered_day_index = v_day_index then public.daily_streaks.current_streak
          when public.daily_streaks.last_answered_day_index = v_day_index - 1 then public.daily_streaks.current_streak + 1
          else 1
        end
      ),
      last_answered_day_index = v_day_index,
      updated_at = now();
  end if;

  return new;
end;
$$;

-- get_daily_question_session: "today's session" lookup now matches on the couple-relative day
-- index (both the session's own created_at and now(), measured from the same couple.created_at
-- origin) instead of a shared calendar date.
create or replace function public.get_daily_question_session()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple_id uuid;
  v_couple_created_at timestamptz;
  v_day_index int;
  v_session_id uuid;
  v_content_id uuid;
  v_tiers text[];
begin
  select id, created_at into v_couple_id, v_couple_created_at
  from public.couples
  where (partner_a_id = auth.uid() or partner_b_id = auth.uid()) and status = 'active'
  limit 1;

  if v_couple_id is null then
    raise exception 'No active couple for the current user';
  end if;

  v_day_index := floor(extract(epoch from (now() - v_couple_created_at)) / 86400)::int;

  select id into v_session_id
  from public.game_sessions
  where couple_id = v_couple_id and is_daily and status != 'abandoned'
    and floor(extract(epoch from (created_at - v_couple_created_at)) / 86400)::int = v_day_index
  limit 1;

  if v_session_id is not null then
    return v_session_id;
  end if;

  v_tiers := case when private.couple_effective_tier(v_couple_id) = 'premium' then array['plus', 'premium'] else array['plus'] end;

  select id into v_content_id
  from public.discussion_topics
  where active and tier = any(v_tiers)
    and id not in (
      select gsr.content_id from public.game_session_rounds gsr
      join public.game_sessions gs on gs.id = gsr.session_id
      where gs.couple_id = v_couple_id and gs.game_type = 'discuss_before_travelling'
    )
  order by random() limit 1;

  if v_content_id is null then
    select id into v_content_id
    from public.discussion_topics where active and tier = any(v_tiers)
    order by random() limit 1;
  end if;

  if v_content_id is null then
    raise exception 'No active discussion content available';
  end if;

  insert into public.game_sessions (couple_id, game_type, initiator_id, status, total_rounds, is_daily)
  values (v_couple_id, 'discuss_before_travelling', auth.uid(), 'active', 1, true)
  returning id into v_session_id;

  insert into public.game_session_rounds (session_id, round_number, content_id)
  values (v_session_id, 1, v_content_id);

  return v_session_id;
end;
$$;

revoke all on function public.get_daily_question_session() from public;
grant execute on function public.get_daily_question_session() to authenticated;

-- get_daily_question_status: same couple-relative day-index match as get_daily_question_session,
-- instead of `created_at::date = current_date`.
create or replace function public.get_daily_question_status()
returns table (
  session_id uuid,
  my_answered boolean,
  partner_answered boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select
    gs.id as session_id,
    coalesce(bool_or(gr.responder_id = auth.uid()), false) as my_answered,
    coalesce(bool_or(gr.responder_id <> auth.uid()), false) as partner_answered
  from public.game_sessions gs
  join public.couples c on c.id = gs.couple_id
  left join public.game_responses gr on gr.session_id = gs.id
  where gs.is_daily
    and public.is_couple_member(gs.couple_id)
    and floor(extract(epoch from (gs.created_at - c.created_at)) / 86400)::int
      = floor(extract(epoch from (now() - c.created_at)) / 86400)::int
  group by gs.id;
$$;

revoke all on function public.get_daily_question_status() from public;
grant execute on function public.get_daily_question_status() to authenticated;
