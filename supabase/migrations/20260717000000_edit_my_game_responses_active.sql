-- Broadens edit_my_game_responses (added in 20260716000000) to also work while the session is
-- still 'active' — "Edit My Answers" is now offered on GameCompletionView too (the "you're
-- finished, waiting for your partner" screen), not just the fully-revealed GameResultsView, so a
-- player needs to be able to redo their own answers before their partner has even finished.
create or replace function public.edit_my_game_responses(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.game_sessions
    where id = p_session_id and public.is_couple_member(couple_id) and status in ('active', 'completed')
  ) then
    raise exception 'Session not found or not editable';
  end if;

  delete from public.game_responses
  where session_id = p_session_id and responder_id = auth.uid();

  -- Only needs resetting if it had already flipped to completed — if the partner hasn't
  -- finished yet the session was already 'active' and stays that way, no trigger needed since
  -- nothing was inserted.
  update public.game_sessions
  set status = 'active', completed_at = null, updated_at = now()
  where id = p_session_id and status = 'completed';
end;
$$;

revoke all on function public.edit_my_game_responses(uuid) from public;
grant execute on function public.edit_my_game_responses(uuid) to authenticated;
