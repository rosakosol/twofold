-- Lets an admin mark a flagged similar/duplicate pair in the Similarity Check tab
-- (site/feedback/src/components/admin/games/DuplicateChecker.tsx) as reviewed-and-acceptable,
-- so it stops surfacing even though the text still scores as similar. Order-independent:
-- row_a_id/row_b_id are always stored with the smaller id first (enforced below), so the
-- client only needs to sort a pair before insert/lookup rather than checking both orders.
create table public.game_content_duplicate_dismissals (
  id uuid primary key default gen_random_uuid(),
  content_type text not null check (
    content_type in ('trivia_questions', 'more_likely_prompts', 'this_or_that_prompts', 'deep_conversation_topics')
  ),
  row_a_id uuid not null,
  row_b_id uuid not null,
  dismissed_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint game_content_duplicate_dismissals_ordered check (row_a_id < row_b_id),
  unique (content_type, row_a_id, row_b_id)
);

alter table public.game_content_duplicate_dismissals enable row level security;

-- Same admin-only gate as the game content tables themselves (see
-- 20260830000900_game_content_admin_write.sql) — only feedback admins can read or write.
create policy "game_content_duplicate_dismissals_admin_all" on public.game_content_duplicate_dismissals
  for all to authenticated
  using (public.is_feedback_admin())
  with check (public.is_feedback_admin());
