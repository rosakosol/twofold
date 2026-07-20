-- Lets the feedback app's admin section (site/feedback/, gated by the already-live
-- public.is_feedback_admin()) manage game content directly instead of via hand-written
-- migrations. Additive alongside each table's existing `select using (true)` policy —
-- RLS policies for the same command OR together, so this only adds insert/update/delete
-- for admins; read access for every authenticated user is unchanged.

create policy "trivia_questions_admin_write" on public.trivia_questions
  for all to authenticated
  using (public.is_feedback_admin())
  with check (public.is_feedback_admin());

create policy "more_likely_prompts_admin_write" on public.more_likely_prompts
  for all to authenticated
  using (public.is_feedback_admin())
  with check (public.is_feedback_admin());

create policy "this_or_that_prompts_admin_write" on public.this_or_that_prompts
  for all to authenticated
  using (public.is_feedback_admin())
  with check (public.is_feedback_admin());

create policy "deep_conversation_topics_admin_write" on public.deep_conversation_topics
  for all to authenticated
  using (public.is_feedback_admin())
  with check (public.is_feedback_admin());

create policy "game_decks_admin_write" on public.game_decks
  for all to authenticated
  using (public.is_feedback_admin())
  with check (public.is_feedback_admin());
