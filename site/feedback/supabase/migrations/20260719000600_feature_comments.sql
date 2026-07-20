create table public.feature_comments (
  id uuid primary key default gen_random_uuid(),
  feature_id uuid not null references public.feature_requests (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index feature_comments_feature_id_idx on public.feature_comments (feature_id);

create trigger trg_feature_comments_touch before update on public.feature_comments
  for each row execute function public.touch_updated_at();

alter table public.feature_comments enable row level security;

create policy "feature_comments_select_all" on public.feature_comments
  for select using (true);

create policy "feature_comments_insert_own" on public.feature_comments
  for insert with check (user_id = auth.uid());

create policy "feature_comments_update_own" on public.feature_comments
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "feature_comments_delete_own_or_admin" on public.feature_comments
  for delete using (user_id = auth.uid() or public.is_feedback_admin());

-- Keeps feature_requests.comment_count accurate without a count(*) on every read.
create or replace function public.sync_feature_comment_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.feature_requests set comment_count = comment_count + 1 where id = new.feature_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.feature_requests set comment_count = greatest(comment_count - 1, 0) where id = old.feature_id;
    return old;
  end if;
  return null;
end;
$$;

create trigger trg_feature_comments_sync_count
  after insert or delete on public.feature_comments
  for each row execute function public.sync_feature_comment_count();
