-- ============================================================
-- A card's tier is its deck's tier, always
-- ============================================================
--
-- The deck is the paywall: start_deck_session refuses a premium deck below premium. But every
-- card carries its own tier too, and the content policies (20260922000000, 20261113000900) and
-- start_deck_session hide a premium card from anyone below premium. So the two can disagree, and
-- when a plus deck holds premium cards, a plus couple opens it and gets "This deck has no
-- content", or a deck that ends early. 20261113000000 fixed that once for 20 decks; changing
-- "Who's More Likely to Make the First Move?" to plus in the dashboard broke it again, because
-- its 12 cards stayed premium.
--
-- Every card now belongs to a deck (20260728000000 and 20260728010000 deleted the rest), and the
-- app only plays through start_deck_session, so the card tier has no job of its own left. From
-- here it just follows the deck:
--
--   1. Every card takes its deck's tier now, in both directions. A plus card in a premium deck
--      becomes premium, which changes nothing anyone can play, since the deck was gated anyway.
--   2. A card inserted into a deck, or moved to another one, takes that deck's tier. Setting a
--      card's tier directly is overwritten the same way: change the deck instead.
--   3. Changing a deck's tier moves all of its cards with it.
--
-- A card with no deck keeps whatever tier it is given. The policies and start_deck_session still
-- read card tiers, unchanged; they just can't disagree with the deck any more.

-- 1. Bring every card into line with its deck.

update public.trivia_questions c set tier = d.tier
from public.game_decks d
where c.deck_id = d.id and c.tier is distinct from d.tier;

update public.more_likely_prompts c set tier = d.tier
from public.game_decks d
where c.deck_id = d.id and c.tier is distinct from d.tier;

update public.this_or_that_prompts c set tier = d.tier
from public.game_decks d
where c.deck_id = d.id and c.tier is distinct from d.tier;

update public.deep_conversation_topics c set tier = d.tier
from public.game_decks d
where c.deck_id = d.id and c.tier is distinct from d.tier;

-- 2. A card in a deck takes the deck's tier. Security definer, so the deck is found whatever the
-- caller can see (adult decks are hidden by policy until both partners opt in).

create or replace function private.card_tier_follows_deck()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tier text;
begin
  if new.deck_id is null then
    return new;
  end if;

  select tier into v_tier from public.game_decks where id = new.deck_id;
  if v_tier is not null then
    new.tier := v_tier;
  end if;
  return new;
end;
$$;

drop trigger if exists trivia_questions_tier_follows_deck on public.trivia_questions;
create trigger trivia_questions_tier_follows_deck
before insert or update of tier, deck_id on public.trivia_questions
for each row execute function private.card_tier_follows_deck();

drop trigger if exists more_likely_prompts_tier_follows_deck on public.more_likely_prompts;
create trigger more_likely_prompts_tier_follows_deck
before insert or update of tier, deck_id on public.more_likely_prompts
for each row execute function private.card_tier_follows_deck();

drop trigger if exists this_or_that_prompts_tier_follows_deck on public.this_or_that_prompts;
create trigger this_or_that_prompts_tier_follows_deck
before insert or update of tier, deck_id on public.this_or_that_prompts
for each row execute function private.card_tier_follows_deck();

drop trigger if exists deep_conversation_topics_tier_follows_deck on public.deep_conversation_topics;
create trigger deep_conversation_topics_tier_follows_deck
before insert or update of tier, deck_id on public.deep_conversation_topics
for each row execute function private.card_tier_follows_deck();

-- 3. A deck's tier change carries its cards with it.

create or replace function private.deck_tier_moves_cards()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_table text;
begin
  if new.tier is not distinct from old.tier then
    return new;
  end if;

  foreach v_table in array array['trivia_questions', 'more_likely_prompts', 'this_or_that_prompts', 'deep_conversation_topics'] loop
    execute format('update public.%I set tier = $1 where deck_id = $2 and tier is distinct from $1', v_table)
      using new.tier, new.id;
  end loop;
  return new;
end;
$$;

drop trigger if exists game_decks_tier_moves_cards on public.game_decks;
create trigger game_decks_tier_moves_cards
after update of tier on public.game_decks
for each row execute function private.deck_tier_moves_cards();

-- Trigger functions only; nobody calls these directly.
revoke all on function private.card_tier_follows_deck() from public, anon, authenticated;
revoke all on function private.deck_tier_moves_cards() from public, anon, authenticated;
