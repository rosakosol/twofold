-- ============================================================
-- Deck length limits: 12 questions, 8 for Deep Conversations
-- ============================================================
--
-- Decks had grown to 16 questions, and Deep Conversations decks to 13. A deck is meant to be one
-- sitting, and a deep conversation question can take an evening; past 12, and past 8 for those,
-- a deck stops being something a couple finishes. 71 active decks were over: 184 questions.
--
-- The extras are switched off and taken out of their deck, keeping each deck's first questions in
-- id order. Taken out, not only switched off: game_decks.question_count counts every row a deck
-- holds (private.deck_content_count) and is only recounted when deck_id changes, so a row merely
-- deactivated would leave the deck advertising its old length, and LocalGameSessionStore builds an
-- offline session's round count from that number. The rows stay, so a session already built on
-- one still finds its card. The 6-question floor for Deep Conversations needs nothing here: no
-- active deck is under it.
--
-- This takes Plus to 479 playable questions and the Premium-inclusive total to 1,831, under the
-- 500+ and 2000+ the plans promise. 20261113000300 adds new decks to bring both back over.
--
-- A trigger then holds the limits for every way content arrives, the admin console included.

-- ---------------------------------------------------------------------------
-- The limits
-- ---------------------------------------------------------------------------

create or replace function private.deck_question_limit(p_game_type game_type)
returns int
language sql
immutable
as $$
  select case p_game_type when 'deep_conversations' then 8 else 12 end
$$;
comment on function private.deck_question_limit(game_type) is
  'Most active questions a deck of this game may hold. Enforced by private.enforce_deck_question_limit.';

-- ---------------------------------------------------------------------------
-- Trim today's decks
-- ---------------------------------------------------------------------------

with ranked as (
  select c.id, row_number() over (partition by c.deck_id order by c.id) as position, private.deck_question_limit(d.game_type) as max_questions
  from public.trivia_questions c
  join public.game_decks d on d.id = c.deck_id and d.active
  where c.active
)
update public.trivia_questions c set active = false, deck_id = null
from ranked r
where c.id = r.id and r.position > r.max_questions;

with ranked as (
  select c.id, row_number() over (partition by c.deck_id order by c.id) as position, private.deck_question_limit(d.game_type) as max_questions
  from public.more_likely_prompts c
  join public.game_decks d on d.id = c.deck_id and d.active
  where c.active
)
update public.more_likely_prompts c set active = false, deck_id = null
from ranked r
where c.id = r.id and r.position > r.max_questions;

with ranked as (
  select c.id, row_number() over (partition by c.deck_id order by c.id) as position, private.deck_question_limit(d.game_type) as max_questions
  from public.this_or_that_prompts c
  join public.game_decks d on d.id = c.deck_id and d.active
  where c.active
)
update public.this_or_that_prompts c set active = false, deck_id = null
from ranked r
where c.id = r.id and r.position > r.max_questions;

with ranked as (
  select c.id, row_number() over (partition by c.deck_id order by c.id) as position, private.deck_question_limit(d.game_type) as max_questions
  from public.deep_conversation_topics c
  join public.game_decks d on d.id = c.deck_id and d.active
  where c.active
)
update public.deep_conversation_topics c set active = false, deck_id = null
from ranked r
where c.id = r.id and r.position > r.max_questions;

-- ---------------------------------------------------------------------------
-- Hold them
-- ---------------------------------------------------------------------------
--
-- Fires when a row would become an active question in a deck: inserted active with a deck, moved
-- into a deck, or switched back on. Security definer, so the count sees every row whatever the
-- caller's tier (the content policies hide premium rows below premium). The deck row is locked
-- first, so two inserts into a deck with one place left cannot both see room.
create or replace function private.enforce_deck_question_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_game_type game_type;
  v_title text;
  v_limit int;
  v_count int;
begin
  if not new.active or new.deck_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.active and old.deck_id is not distinct from new.deck_id then
    return new;
  end if;

  select game_type, title into v_game_type, v_title
  from public.game_decks where id = new.deck_id
  for update;
  if v_game_type is null then
    return new;
  end if;

  v_limit := private.deck_question_limit(v_game_type);
  execute format('select count(*) from public.%I where deck_id = $1 and active and id <> $2', tg_table_name)
    into v_count using new.deck_id, new.id;

  if v_count >= v_limit then
    raise exception '"%" is full: a deck holds at most % questions. Start a new deck for more.', v_title, v_limit
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger trivia_questions_deck_question_limit
before insert or update of active, deck_id on public.trivia_questions
for each row execute function private.enforce_deck_question_limit();

create trigger more_likely_prompts_deck_question_limit
before insert or update of active, deck_id on public.more_likely_prompts
for each row execute function private.enforce_deck_question_limit();

create trigger this_or_that_prompts_deck_question_limit
before insert or update of active, deck_id on public.this_or_that_prompts
for each row execute function private.enforce_deck_question_limit();

create trigger deep_conversation_topics_deck_question_limit
before insert or update of active, deck_id on public.deep_conversation_topics
for each row execute function private.enforce_deck_question_limit();
