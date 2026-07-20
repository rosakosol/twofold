-- Composite primary key IS the "one vote per user" uniqueness constraint the spec asks
-- for — no separate unique index needed.
create table public.feature_votes (
  feature_id uuid not null references public.feature_requests (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (feature_id, user_id)
);

create index feature_votes_user_id_idx on public.feature_votes (user_id);
-- Supports the "popular this week" query (Phase 9): count votes per feature within a
-- trailing window without a full table scan.
create index feature_votes_created_at_idx on public.feature_votes (created_at);

alter table public.feature_votes enable row level security;

-- Public select: needed so anyone can render "N votes" / voter avatar stacks, and so a
-- signed-in visitor can tell whether *they've* already voted on a request.
create policy "feature_votes_select_all" on public.feature_votes
  for select using (true);

create policy "feature_votes_insert_own" on public.feature_votes
  for insert with check (user_id = auth.uid());

create policy "feature_votes_delete_own" on public.feature_votes
  for delete using (user_id = auth.uid());

-- Keeps feature_requests.upvote_count accurate without a count(*) on every read.
create or replace function public.sync_feature_upvote_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.feature_requests set upvote_count = upvote_count + 1 where id = new.feature_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.feature_requests set upvote_count = greatest(upvote_count - 1, 0) where id = old.feature_id;
    return old;
  end if;
  return null;
end;
$$;

create trigger trg_feature_votes_sync_count
  after insert or delete on public.feature_votes
  for each row execute function public.sync_feature_upvote_count();
