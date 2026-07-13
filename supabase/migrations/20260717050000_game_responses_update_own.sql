-- Lets a player revisit and change an already-answered round mid-game (the new back/forward
-- navigator replacing the old "Leave" button — see GameSessionStore.goBack/goForward). The
-- client now upserts on submit (see BackendService.submitGameResponse's onConflict), which
-- resolves to an UPDATE for a round that already has a response row; without this policy that
-- UPDATE is silently blocked by RLS (there was previously no UPDATE policy on this table at
-- all — only INSERT and SELECT). Mirrors the existing INSERT policy's WITH CHECK exactly.
create policy "game_responses_update_own_active" on public.game_responses
  for update using (
    responder_id = auth.uid()
    and exists (
      select 1 from public.game_sessions gs
      where gs.id = game_responses.session_id and is_couple_member(gs.couple_id) and is_couple_active(gs.couple_id)
    )
  )
  with check (
    responder_id = auth.uid()
    and exists (
      select 1 from public.game_sessions gs
      where gs.id = game_responses.session_id and is_couple_member(gs.couple_id) and is_couple_active(gs.couple_id)
    )
  );
