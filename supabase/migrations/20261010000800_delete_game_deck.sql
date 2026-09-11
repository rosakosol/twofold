-- Deleting a deck from the admin UI could not work. trivia_questions.deck_id,
-- more_likely_prompts.deck_id, this_or_that_prompts.deck_id, deep_conversation_topics.deck_id
-- and game_sessions.deck_id are all NO ACTION foreign keys, so the moment a deck had a single
-- question in it — which is the only state a real deck is ever in — Postgres refused the delete.
-- The confirm dialog's warning ("questions will keep a deck_id pointing at a deleted deck") was
-- describing an outcome the database never permitted.
--
-- A deck is its questions, so deleting one takes them with it. That has to be a single
-- transaction — the content rows, the sessions played from the deck, then the deck — which is
-- why it is one RPC and not a sequence of client calls that can half-fail and strand a deck
-- with its questions already gone.
--
-- Why the sessions go too: game_session_rounds.content_id is deliberately not a foreign key
-- (it is polymorphic across the four content tables), so nothing would stop a session outliving
-- the questions it points at — it would simply replay as a game whose rounds have no content.
-- 20260731000000_delete_inactive_game_decks.sql deleted them by hand for exactly this reason;
-- rounds and responses cascade from game_sessions already.
--
-- Gated on the same public.is_feedback_admin() check that the game_decks write policy uses.
-- security definer so the sweep does not depend on the calling admin's own table grants, the
-- same reason the question_count triggers are (20260830001000).

create or replace function public.delete_game_deck(p_deck_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_questions int := 0;
  v_sessions int := 0;
  v_deleted int;
begin
  if not public.is_feedback_admin() then
    raise exception 'Only an admin can delete a game deck' using errcode = '42501';
  end if;

  if not exists (select 1 from public.game_decks where id = p_deck_id) then
    raise exception 'Deck % does not exist', p_deck_id using errcode = 'P0002';
  end if;

  -- All four content tables, not just the one matching the deck's game_type: nothing constrains
  -- a row in another table from carrying this deck_id, and a delete that leaves one behind puts
  -- the FK back in the way.
  delete from public.trivia_questions where deck_id = p_deck_id;
  get diagnostics v_deleted = row_count;
  v_questions := v_questions + v_deleted;

  delete from public.more_likely_prompts where deck_id = p_deck_id;
  get diagnostics v_deleted = row_count;
  v_questions := v_questions + v_deleted;

  delete from public.this_or_that_prompts where deck_id = p_deck_id;
  get diagnostics v_deleted = row_count;
  v_questions := v_questions + v_deleted;

  delete from public.deep_conversation_topics where deck_id = p_deck_id;
  get diagnostics v_deleted = row_count;
  v_questions := v_questions + v_deleted;

  delete from public.game_sessions where deck_id = p_deck_id;
  get diagnostics v_sessions = row_count;

  delete from public.game_decks where id = p_deck_id;

  return json_build_object('questions_deleted', v_questions, 'sessions_deleted', v_sessions);
end;
$$;

grant execute on function public.delete_game_deck(uuid) to authenticated;
