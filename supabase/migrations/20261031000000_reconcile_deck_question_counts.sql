-- `game_decks.question_count` has been wrong for 36 of 191 decks. This makes it right.
--
-- The column is a denormalised count of a deck's rows in whichever of the four content tables its
-- game type points at. It was hand-maintained from the day it was added (20260714030000) — every
-- seed migration recomputed it with its own `update ... set question_count = (select count(*) ...)`
-- over the ids that migration happened to touch. Triggers took the job over in 20260830001000, and
-- keep it correct from that point forward, but that migration added no backfill. So every deck
-- whose count was already wrong stayed wrong, invisibly, and still is.
--
-- What it costs. `LocalGameSessionStore.create` builds an offline session with `totalRounds` from
-- this column, and the Games hub shows it as the deck's length. 24 decks overstate by 5 to 8, so a
-- deck advertising 15 questions hands back 7 and a session cannot reach the end it promised. The
-- other 12 understate by 1 or 2, which is quieter: those questions exist and are never played.
--
-- Not the CMS. A local database built from migrations alone, with no Studio edits ever applied,
-- reproduces the same 36 — which is what points at the missing backfill rather than at anything
-- anyone did in the admin UI.

-- ---------------------------------------------------------------------------
-- One definition of "how many rows does this deck have"
-- ---------------------------------------------------------------------------
--
-- The mapping from game type to content table was previously written out by hand in every migration
-- that needed it, which is most of the seed migrations, the trigger functions, and now this. That
-- is precisely how the counts drifted apart in the first place: many copies, each correct for the
-- decks its own author was thinking about.
--
-- In `private`, not `public`: nothing calls this over PostgREST, and an unreachable-by-API helper is
-- the right default for something that exists to be called from SQL. (The opposite case —
-- `dormancy_cohort` — is in `public` precisely because an Edge Function does reach it.)
create or replace function private.deck_content_count(p_deck_id uuid, p_game_type game_type)
returns bigint
language sql
stable
as $$
  select case p_game_type
    when 'trivia_battle' then (select count(*) from public.trivia_questions where deck_id = p_deck_id)
    when 'more_likely' then (select count(*) from public.more_likely_prompts where deck_id = p_deck_id)
    when 'this_or_that' then (select count(*) from public.this_or_that_prompts where deck_id = p_deck_id)
    when 'deep_conversations' then (select count(*) from public.deep_conversation_topics where deck_id = p_deck_id)
  end
$$;

comment on function private.deck_content_count(uuid, game_type) is
  'Rows a deck actually has, by game type. Null for a type with no content table, which is how '
  'callers notice a fifth type was added without extending this rather than silently counting zero.';

-- ---------------------------------------------------------------------------
-- The correction
-- ---------------------------------------------------------------------------
--
-- Every deck, not a list of ids. The id lists are how this drifted: each migration fixed the decks
-- it knew about and left the rest, and eventually "the rest" was 36.
update public.game_decks d
set question_count = private.deck_content_count(d.id, d.game_type)
where private.deck_content_count(d.id, d.game_type) is not null
  and d.question_count is distinct from private.deck_content_count(d.id, d.game_type);

-- Refuses to finish if anything is still inconsistent.
--
-- A silent partial fix is the failure this whole migration exists because of: the counts were wrong
-- for months and nothing said so. A fifth game type gaining a content table without being added to
-- `deck_content_count` fails here rather than leaving a new generation of quietly wrong numbers.
do $$
declare
  v_unmapped int;
  v_wrong int;
begin
  select count(*) into v_unmapped
  from public.game_decks d
  where private.deck_content_count(d.id, d.game_type) is null;

  if v_unmapped > 0 then
    raise exception 'reconcile: % decks have a game type deck_content_count cannot count', v_unmapped;
  end if;

  select count(*) into v_wrong
  from public.game_decks d
  where d.question_count is distinct from private.deck_content_count(d.id, d.game_type);

  if v_wrong > 0 then
    raise exception 'reconcile: % decks still disagree with their content', v_wrong;
  end if;
end;
$$;
