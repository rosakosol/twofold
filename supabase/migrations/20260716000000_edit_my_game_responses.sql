-- Lets a player re-answer their own rounds on an already-completed session ("Edit My Answers"
-- from GameResultsView's toolbar menu) — deletes only the caller's own game_responses rows
-- (never the partner's) and resets the session back to 'active' so GameSessionStore.isRevealed
-- goes false and the couple's shared game view drops back into the round-answering flow.
-- advance_game_session (fires on every game_responses insert) naturally flips status back to
-- 'completed' once the caller finishes resubmitting all rounds and the partner's untouched
-- original answers are still there — no separate re-reveal logic needed.
create or replace function public.edit_my_game_responses(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.game_sessions
    where id = p_session_id and public.is_couple_member(couple_id) and status = 'completed'
  ) then
    raise exception 'Session not found or not completed';
  end if;

  delete from public.game_responses
  where session_id = p_session_id and responder_id = auth.uid();

  update public.game_sessions
  set status = 'active', completed_at = null, updated_at = now()
  where id = p_session_id;
end;
$$;

revoke all on function public.edit_my_game_responses(uuid) from public;
grant execute on function public.edit_my_game_responses(uuid) to authenticated;
