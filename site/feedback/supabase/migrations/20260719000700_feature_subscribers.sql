-- Lets a user follow a request's updates without voting on it. Private bookkeeping,
-- unlike votes/comments — nobody else needs to see who's subscribed to what.
create table public.feature_subscribers (
  feature_id uuid not null references public.feature_requests (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (feature_id, user_id)
);

alter table public.feature_subscribers enable row level security;

create policy "feature_subscribers_select_own_or_admin" on public.feature_subscribers
  for select using (user_id = auth.uid() or public.is_feedback_admin());

create policy "feature_subscribers_insert_own" on public.feature_subscribers
  for insert with check (user_id = auth.uid());

create policy "feature_subscribers_delete_own" on public.feature_subscribers
  for delete using (user_id = auth.uid());
