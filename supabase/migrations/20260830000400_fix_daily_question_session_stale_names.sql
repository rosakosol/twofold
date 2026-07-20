-- `get_daily_question_session()` was redefined by 20260829000500 (per-couple day-index boundary)
-- but still referenced `discussion_topics` / the `discuss_before_travelling` game_type value —
-- both renamed to `deep_conversation_topics` / `deep_conversations` back on 2026-08-02
-- (20260802000000_rename_deep_conversations_and_trivia_battle.sql). plpgsql doesn't validate
-- relation names at CREATE time, so the function deployed cleanly but threw
-- `relation "public.discussion_topics" does not exist` on every real call — the cause of
-- "Couldn't load today's question" for every couple. Otherwise identical to the 20260829000500
-- version (day-index "today" match unchanged), just with the correct current names restored.
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
  from public.deep_conversation_topics
  where active and tier = any(v_tiers)
    and id not in (
      select gsr.content_id from public.game_session_rounds gsr
      join public.game_sessions gs on gs.id = gsr.session_id
      where gs.couple_id = v_couple_id and gs.game_type = 'deep_conversations'
    )
  order by random() limit 1;

  if v_content_id is null then
    select id into v_content_id
    from public.deep_conversation_topics where active and tier = any(v_tiers)
    order by random() limit 1;
  end if;

  if v_content_id is null then
    raise exception 'No active discussion content available';
  end if;

  insert into public.game_sessions (couple_id, game_type, initiator_id, status, total_rounds, is_daily)
  values (v_couple_id, 'deep_conversations', auth.uid(), 'active', 1, true)
  returning id into v_session_id;

  insert into public.game_session_rounds (session_id, round_number, content_id)
  values (v_session_id, 1, v_content_id);

  return v_session_id;
end;
$$;

revoke all on function public.get_daily_question_session() from public;
grant execute on function public.get_daily_question_session() to authenticated;

drop function if exists public.debug_daily_question_diagnostics();
