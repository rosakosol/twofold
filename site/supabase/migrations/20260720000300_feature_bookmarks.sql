-- Personal "save for later" list — distinct from voting (public signal, affects
-- upvote_count) and subscribing (notification opt-in). Bookmarks are private, so unlike
-- feature_votes there's no public-select policy: only the owning user can ever see
-- their own bookmark rows.
create table public.feature_bookmarks (
  feature_id uuid not null references public.feature_requests (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (feature_id, user_id)
);

create index feature_bookmarks_user_id_idx on public.feature_bookmarks (user_id, created_at desc);

alter table public.feature_bookmarks enable row level security;

create policy "feature_bookmarks_select_own" on public.feature_bookmarks
  for select using (user_id = auth.uid());

create policy "feature_bookmarks_insert_own" on public.feature_bookmarks
  for insert with check (user_id = auth.uid());

create policy "feature_bookmarks_delete_own" on public.feature_bookmarks
  for delete using (user_id = auth.uid());
