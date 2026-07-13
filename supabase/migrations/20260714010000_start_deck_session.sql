-- Starts a session scoped to one curated deck's tagged content — the deck-equivalent of
-- start_game_session, but no random sampling/no-repeat logic is needed since a deck is already a
-- small, fixed curated set meant to be played as-is (round count = however many rows are tagged
-- to it). Tier eligibility is enforced server-side too, not just hidden client-side, since a
-- premium deck's content shouldn't be startable by a client that bypasses the UI gate.

create or replace function public.start_deck_session(p_deck_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
    when 'travel_trivia' then
      select array_agg(id) into v_content_ids from public.trivia_questions where deck_id = p_deck_id and active;
    when 'more_likely' then
      select array_agg(id) into v_content_ids from public.more_likely_prompts where deck_id = p_deck_id and active;
    when 'this_or_that' then
      select array_agg(id) into v_content_ids from public.this_or_that_prompts where deck_id = p_deck_id and active;
    when 'discuss_before_travelling' then
      select array_agg(id) into v_content_ids from public.discussion_topics where deck_id = p_deck_id and active;
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
$$;

revoke all on function public.start_deck_session(uuid) from public;
grant execute on function public.start_deck_session(uuid) to authenticated;

-- Lets a client find "do we already have a session for this deck" the same way GameEntryView
-- does for regular game types (fetchGameSessions + filter client-side would also work, but an
-- index makes that filter cheap once a couple has played many decks over time).
create index game_sessions_deck_id_idx on public.game_sessions (deck_id) where deck_id is not null;
