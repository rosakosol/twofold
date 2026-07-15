-- Renames two game types:
--   discuss_before_travelling -> deep_conversations (game_type enum), discussion_topics -> deep_conversation_topics (table)
--   travel_trivia -> trivia_battle (game_type enum)
-- ALTER TYPE ... RENAME VALUE and ALTER TABLE ... RENAME TO update every column/FK/RLS-policy
-- attachment automatically via catalog OID. What they don't touch: function bodies that hardcode
-- the old value/table name as a string literal, and the index/policy names themselves (cosmetic
-- but renamed here too for consistency) — those are handled explicitly below.

alter type public.game_type rename value 'discuss_before_travelling' to 'deep_conversations';
alter type public.game_type rename value 'travel_trivia' to 'trivia_battle';

alter table public.discussion_topics rename to deep_conversation_topics;
alter index discussion_topics_deck_id_idx rename to deep_conversation_topics_deck_id_idx;
alter policy "discussion_topics_select_authenticated" on public.deep_conversation_topics
  rename to "deep_conversation_topics_select_authenticated";

create or replace function public.start_game_session(p_game_type game_type)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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

  v_round_count := case when p_game_type = 'deep_conversations' then 8 else 12 end;
  v_tiers := case when private.couple_effective_tier(v_couple_id) = 'premium' then array['plus', 'premium'] else array['plus'] end;

  case p_game_type
    when 'trivia_battle' then
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
    when 'deep_conversations' then
      select array_agg(id) into v_content_ids from (
        select id from public.deep_conversation_topics
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
          select id from public.deep_conversation_topics where active and tier = any(v_tiers) order by random() limit v_round_count
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
$function$;

create or replace function public.get_daily_question_session()
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
$function$;

create or replace function public.start_deck_session(p_deck_id uuid)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_couple_id uuid;
  v_session_id uuid;
  v_deck record;
  v_content_ids uuid[];
  v_round_count int;
  i int;
begin
  select id into v_couple_id
  from public.couples
  where (partner_a_id = auth.uid() or partner_b_id = auth.uid()) and status = 'active'
  limit 1;

  if v_couple_id is null then
    raise exception 'No active couple for the current user';
  end if;

  select * into v_deck from public.game_decks where id = p_deck_id and active;
  if v_deck is null then
    raise exception 'Deck not found';
  end if;

  if v_deck.tier = 'premium' and private.couple_effective_tier(v_couple_id) <> 'premium' then
    raise exception 'This deck requires Premium';
  end if;

  case v_deck.game_type
    when 'trivia_battle' then
      select array_agg(id) into v_content_ids from public.trivia_questions where deck_id = p_deck_id and active;
    when 'more_likely' then
      select array_agg(id) into v_content_ids from public.more_likely_prompts where deck_id = p_deck_id and active;
    when 'this_or_that' then
      select array_agg(id) into v_content_ids from public.this_or_that_prompts where deck_id = p_deck_id and active;
    when 'deep_conversations' then
      select array_agg(id) into v_content_ids from public.deep_conversation_topics where deck_id = p_deck_id and active;
  end case;

  if v_content_ids is null or array_length(v_content_ids, 1) = 0 then
    raise exception 'This deck has no content';
  end if;

  v_round_count := array_length(v_content_ids, 1);

  insert into public.game_sessions (couple_id, game_type, initiator_id, status, total_rounds, deck_id)
  values (v_couple_id, v_deck.game_type, auth.uid(), 'active', v_round_count, p_deck_id)
  returning id into v_session_id;

  for i in 1..v_round_count loop
    insert into public.game_session_rounds (session_id, round_number, content_id)
    values (v_session_id, i, v_content_ids[i]);
  end loop;

  return v_session_id;
end;
$function$;
