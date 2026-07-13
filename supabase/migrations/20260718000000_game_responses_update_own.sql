-- Re-adds the UPDATE policy dropped by 20260717060000 — the game round back button is back
-- (revisiting the previous round to change an answer resolves to an UPDATE via upsert), so
-- clients need permission to update their own in-flight responses again.
create policy "game_responses_update_own_active" on public.game_responses
  for update using (
    responder_id = auth.uid()
    and exists (select 1 from public.game_sessions gs where gs.id = game_responses.session_id and is_couple_member(gs.couple_id) and is_couple_active(gs.couple_id))
  )
  with check (
    responder_id = auth.uid()
    and exists (select 1 from public.game_sessions gs where gs.id = game_responses.session_id and is_couple_member(gs.couple_id) and is_couple_active(gs.couple_id))
  );
