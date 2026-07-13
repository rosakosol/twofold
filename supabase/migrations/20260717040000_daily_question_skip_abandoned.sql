-- get_daily_question_session's "find today's session" lookup matched on `is_daily and
-- created_at::date = current_date` alone, with no status filter — an abandoned daily session
-- (from the now-removed in-game "Leave" button) was therefore returned again on every
-- subsequent call for the rest of that day, permanently stuck showing "This game was left
-- unfinished" with no way to retry. Excluding abandoned sessions here means a fresh one gets
-- created instead, self-healing rather than requiring a manual reset path.
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
  where couple_id = v_couple_id and is_daily and created_at::date = current_date and status != 'abandoned'
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
