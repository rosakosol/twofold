-- ---------------------------------------------------------------------------
-- start_deck_session: a lapsed solo player is not Premium
-- ---------------------------------------------------------------------------
--
-- The solo branch of start_deck_session read `profiles.subscription_tier` bare:
--
--   else coalesce((select subscription_tier from public.profiles where id = auth.uid()), 'plus')
--
-- That column is deliberately never cleared when a subscription lapses (see 20260912000000), so an
-- unpaired player whose Premium ended months ago still passed "This deck requires Premium" and got
-- a session built from premium cards. Every sibling — start_sudoku_session, start_word_guess_session,
-- start_word_search_session, viewer_effective_tier — reads `case when subscription_active then
-- subscription_tier end`, and three of them carry a comment warning about exactly this shape. This
-- one was missed in 20260923000000 and copied forward unchanged through 20261113000000,
-- 20261113001500 and 20261113000900.
--
-- The cards themselves stayed hidden — the content policies go through viewer_effective_tier, which
-- does check `subscription_active` — so the lapsed player got a session whose every round was a card
-- the app could not load, which is the "you've finished" screen 20261113000000 was written to stop.
-- The paywall answer was wrong and the game was broken; both are fixed by asking the right question.
--
-- Also refuses an unauthenticated caller up front and takes execute away from anon. anon could call
-- this (it was never revoked) and reach the deck lookup and tier messages before failing on the
-- not-null initiator; nothing anon can do here is legitimate.
--
-- Replaced whole, from 20261113000900, which is the latest definition. Only the auth check and the
-- solo tier line differ.

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
  v_effective_tier text;
  i int;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select id into v_couple_id
  from public.couples
  where (partner_a_id = auth.uid() or partner_b_id = auth.uid()) and status = 'active'
  limit 1;

  select * into v_deck from public.game_decks where id = p_deck_id and active;
  if v_deck is null then
    raise exception 'Deck not found';
  end if;

  if v_couple_id is null and v_deck.game_type = 'more_likely' then
    raise exception 'This game needs a partner';
  end if;

  v_effective_tier := case
    when v_couple_id is not null then private.couple_effective_tier(v_couple_id)
    -- `subscription_active` decides, not the tier column, which outlives a lapse (see header).
    else coalesce(
      (select case when subscription_active then subscription_tier end
       from public.profiles where id = auth.uid()),
      'plus'
    )
  end;

  if v_deck.tier = 'premium' and v_effective_tier <> 'premium' then
    raise exception 'This deck requires Premium';
  end if;

  -- 18+ decks need both partners to have opted in (see the header). Checked here as well as in the
  -- read policies because this function is a definer and would otherwise build the session anyway.
  if v_deck.adult and not private.viewer_adult_unlocked() then
    raise exception 'This deck needs both partners to turn on 18+ questions';
  end if;

  -- The resume. Newest first, because the duplicates this migration stops creating already exist
  -- in production and the most recent one is the one a player was last looking at.
  select id into v_session_id
  from public.game_sessions
  where deck_id = p_deck_id
    and status in ('active', 'waiting_for_partner')
    and (
      (v_couple_id is not null and couple_id = v_couple_id)
      or (v_couple_id is null and couple_id is null and initiator_id = auth.uid())
    )
  order by created_at desc
  limit 1;

  if v_session_id is not null then
    return v_session_id;
  end if;

  -- Only cards the couple can read. The content policies hide a premium card from anyone below
  -- premium (20260922000000); a round built on one is a round the app has no card for, and it
  -- showed "you've finished" in its place.
  case v_deck.game_type
    when 'trivia_battle' then
      select array_agg(id) into v_content_ids from public.trivia_questions
      where deck_id = p_deck_id and active and (tier is distinct from 'premium' or v_effective_tier = 'premium');
    when 'more_likely' then
      select array_agg(id) into v_content_ids from public.more_likely_prompts
      where deck_id = p_deck_id and active and (tier is distinct from 'premium' or v_effective_tier = 'premium');
    when 'this_or_that' then
      select array_agg(id) into v_content_ids from public.this_or_that_prompts
      where deck_id = p_deck_id and active and (tier is distinct from 'premium' or v_effective_tier = 'premium');
    when 'deep_conversations' then
      select array_agg(id) into v_content_ids from public.deep_conversation_topics
      where deck_id = p_deck_id and active and (tier is distinct from 'premium' or v_effective_tier = 'premium');
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

revoke all on function public.start_deck_session(uuid) from public, anon;
grant execute on function public.start_deck_session(uuid) to authenticated;
