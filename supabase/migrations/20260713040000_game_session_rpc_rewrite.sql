-- Rewrites start_game_session for tier-aware, no-repeat content selection and per-game-type
-- round counts (was a flat 5 for every game); extends the existing advance_game_session trigger
-- to drive the Daily Activity streak; adds get_daily_question_session, the RPC behind the Daily
-- Activity card (an ordinary 1-round discuss_before_travelling session, reusing every bit of the
-- existing session engine rather than building a parallel content/answer system).

-- ---------------------------------------------------------------------------
-- Couple's effective content tier — the max of both partners' subscription_tier, treating a
-- null tier (pre-existing subscribers, from before this column existed) as 'plus' so nobody who
-- was already subscribed loses access to content they could already play.
-- ---------------------------------------------------------------------------

create or replace function private.couple_effective_tier(p_couple_id uuid)
returns text
language sql
security definer
stable
set search_path = public
as $$
  select case
    when bool_or(coalesce(p.subscription_tier, 'plus') = 'premium') then 'premium'
    else 'plus'
  end
  from public.couples c
  join public.profiles p on p.id in (c.partner_a_id, c.partner_b_id)
  where c.id = p_couple_id;
$$;

-- ---------------------------------------------------------------------------
-- start_game_session: round count is now per-game-type (8 for discussion, 12 for everything
-- else — was a flat 5). Content selection is tier-filtered and excludes content this couple has
-- already played in a past session of the same game_type; if the eligible-and-unseen pool is
-- smaller than the round count (couple has exhausted it), falls back to the tier-filtered pool
-- without the exclusion rather than raising — a couple should never hit a hard error just
-- because they've played enough.
-- ---------------------------------------------------------------------------

create or replace function public.start_game_session(p_game_type public.game_type)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple_id uuid;
  v_session_id uuid;
  v_content_ids uuid[];
  v_round_count int;
  v_tiers text[];
  i int;
begin
  select id into v_couple_id
  from public.couples
  where (partner_a_id = auth.uid() or partner_b_id = auth.uid()) and status = 'active'
  limit 1;

  if v_couple_id is null then
    raise exception 'No active couple for the current user';
  end if;

  v_round_count := case when p_game_type = 'discuss_before_travelling' then 8 else 12 end;
  v_tiers := case when private.couple_effective_tier(v_couple_id) = 'premium' then array['plus', 'premium'] else array['plus'] end;

  case p_game_type
    when 'travel_trivia' then
      select array_agg(id) into v_content_ids from (
        select id from public.trivia_questions
        where active and tier = any(v_tiers)
          and id not in (
            select gsr.content_id from public.game_session_rounds gsr
            join public.game_sessions gs on gs.id = gsr.session_id
            where gs.couple_id = v_couple_id and gs.game_type = p_game_type
          )
        order by random() limit v_round_count
      ) t;
      if v_content_ids is null or array_length(v_content_ids, 1) < v_round_count then
        select array_agg(id) into v_content_ids from (
          select id from public.trivia_questions where active and tier = any(v_tiers) order by random() limit v_round_count
        ) t;
      end if;
    when 'more_likely' then
      select array_agg(id) into v_content_ids from (
        select id from public.more_likely_prompts
        where active and tier = any(v_tiers)
          and id not in (
            select gsr.content_id from public.game_session_rounds gsr
            join public.game_sessions gs on gs.id = gsr.session_id
            where gs.couple_id = v_couple_id and gs.game_type = p_game_type
          )
        order by random() limit v_round_count
      ) t;
      if v_content_ids is null or array_length(v_content_ids, 1) < v_round_count then
        select array_agg(id) into v_content_ids from (
          select id from public.more_likely_prompts where active and tier = any(v_tiers) order by random() limit v_round_count
        ) t;
      end if;
    when 'this_or_that' then
      select array_agg(id) into v_content_ids from (
        select id from public.this_or_that_prompts
        where active and tier = any(v_tiers)
          and id not in (
            select gsr.content_id from public.game_session_rounds gsr
            join public.game_sessions gs on gs.id = gsr.session_id
            where gs.couple_id = v_couple_id and gs.game_type = p_game_type
          )
        order by random() limit v_round_count
      ) t;
      if v_content_ids is null or array_length(v_content_ids, 1) < v_round_count then
        select array_agg(id) into v_content_ids from (
          select id from public.this_or_that_prompts where active and tier = any(v_tiers) order by random() limit v_round_count
        ) t;
      end if;
    when 'discuss_before_travelling' then
      select array_agg(id) into v_content_ids from (
        select id from public.discussion_topics
        where active and tier = any(v_tiers)
          and id not in (
            select gsr.content_id from public.game_session_rounds gsr
            join public.game_sessions gs on gs.id = gsr.session_id
            where gs.couple_id = v_couple_id and gs.game_type = p_game_type
          )
        order by random() limit v_round_count
      ) t;
      if v_content_ids is null or array_length(v_content_ids, 1) < v_round_count then
        select array_agg(id) into v_content_ids from (
          select id from public.discussion_topics where active and tier = any(v_tiers) order by random() limit v_round_count
        ) t;
      end if;
  end case;

  if v_content_ids is null or array_length(v_content_ids, 1) < v_round_count then
    raise exception 'Not enough active content to start this game';
  end if;

  insert into public.game_sessions (couple_id, game_type, initiator_id, status, total_rounds)
  values (v_couple_id, p_game_type, auth.uid(), 'active', v_round_count)
  returning id into v_session_id;

  for i in 1..v_round_count loop
    insert into public.game_session_rounds (session_id, round_number, content_id)
    values (v_session_id, i, v_content_ids[i]);
  end loop;

  return v_session_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- advance_game_session: unchanged completion logic, plus a new block driving daily_streaks
-- whenever the response being inserted belongs to an is_daily session. Increments the moment
-- *either* partner answers (not both) — the on-conflict branch is a same-day no-op if the
-- second partner (or a re-check) fires again the same day.
-- ---------------------------------------------------------------------------

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
begin
  select total_rounds, couple_id, is_daily into v_total_rounds, v_couple_id, v_is_daily
  from public.game_sessions where id = new.session_id;

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

  if v_is_daily then
    insert into public.daily_streaks (couple_id, current_streak, longest_streak, last_answered_date, updated_at)
    values (v_couple_id, 1, 1, current_date, now())
    on conflict (couple_id) do update set
      current_streak = case
        when public.daily_streaks.last_answered_date = current_date then public.daily_streaks.current_streak
        when public.daily_streaks.last_answered_date = current_date - 1 then public.daily_streaks.current_streak + 1
        else 1
      end,
      longest_streak = greatest(
        public.daily_streaks.longest_streak,
        case
          when public.daily_streaks.last_answered_date = current_date then public.daily_streaks.current_streak
          when public.daily_streaks.last_answered_date = current_date - 1 then public.daily_streaks.current_streak + 1
          else 1
        end
      ),
      last_answered_date = current_date,
      updated_at = now();
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- get_daily_question_session: returns today's daily session id, creating it (a normal 1-round
-- discuss_before_travelling session flagged is_daily) on first request each day. Same
-- tier-filtered, no-repeat-with-fallback content selection as start_game_session.
-- ---------------------------------------------------------------------------

create or replace function public.get_daily_question_session()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple_id uuid;
  v_session_id uuid;
  v_content_id uuid;
  v_tiers text[];
begin
  select id into v_couple_id
  from public.couples
  where (partner_a_id = auth.uid() or partner_b_id = auth.uid()) and status = 'active'
  limit 1;

  if v_couple_id is null then
    raise exception 'No active couple for the current user';
  end if;

  select id into v_session_id
  from public.game_sessions
  where couple_id = v_couple_id and is_daily and created_at::date = current_date
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
