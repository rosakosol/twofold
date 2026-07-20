create table public.developer_updates (
  id uuid primary key default gen_random_uuid(),
  feature_id uuid not null references public.feature_requests (id) on delete cascade,
  author_id uuid references public.profiles (id) on delete set null,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index developer_updates_feature_id_idx on public.developer_updates (feature_id);

alter table public.developer_updates enable row level security;

create policy "developer_updates_select_all" on public.developer_updates
  for select using (true);

create policy "developer_updates_insert_admin" on public.developer_updates
  for insert with check (public.is_feedback_admin());

create policy "developer_updates_update_admin" on public.developer_updates
  for update using (public.is_feedback_admin()) with check (public.is_feedback_admin());

create policy "developer_updates_delete_admin" on public.developer_updates
  for delete using (public.is_feedback_admin());
