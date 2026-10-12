-- ============================================================
-- A deck's cards follow the deck's tier
-- ============================================================
--
-- 20 plus decks held 114 premium cards. 20260726000000 built new decks from spare cards in the
-- shared pool, picked by category and never by tier, so premium cards went into plus decks. The
-- deck's tier is the paywall — start_deck_session refuses a premium deck below premium — but the
-- content policies (20260922000000) also hide each premium card from anyone below premium. A plus
-- couple could open those decks and then could not read their cards: seven of them had no
-- readable card at all, and the app, with no card to draw, showed "you've finished" on a deck
-- nobody had played. The other thirteen ended early, at their first premium card.
--
-- Cards in an active plus deck become plus, so those decks play in full. Only that direction: a
-- plus card in a premium deck is harmless, since the deck itself is gated. Deck tiers do not move
-- (60 plus, 128 premium).
--
-- start_deck_session also stops building rounds from cards the couple cannot read, so a card
-- tagged premium inside a plus deck later can only shorten that deck, never break it.

update public.trivia_questions c set tier = 'plus'
from public.game_decks d
where c.deck_id = d.id and d.active and d.tier = 'plus' and c.tier = 'premium';

update public.more_likely_prompts c set tier = 'plus'
from public.game_decks d
where c.deck_id = d.id and d.active and d.tier = 'plus' and c.tier = 'premium';

update public.this_or_that_prompts c set tier = 'plus'
from public.game_decks d
where c.deck_id = d.id and d.active and d.tier = 'plus' and c.tier = 'premium';

update public.deep_conversation_topics c set tier = 'plus'
from public.game_decks d
where c.deck_id = d.id and d.active and d.tier = 'plus' and c.tier = 'premium';

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
    else coalesce((select subscription_tier from public.profiles where id = auth.uid()), 'plus')
  end;

  if v_deck.tier = 'premium' and v_effective_tier <> 'premium' then
    raise exception 'This deck requires Premium';
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
