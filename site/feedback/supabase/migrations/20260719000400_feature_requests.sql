create table public.feature_requests (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 3 and 140),
  slug text not null unique,
  description text not null default '',
  category public.feedback_request_category not null,
  status public.feedback_request_status not null default 'requested',
  author_id uuid references public.profiles (id) on delete set null,
  upvote_count int not null default 0,
  comment_count int not null default 0,
  is_pinned boolean not null default false,
  merged_into uuid references public.feature_requests (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index feature_requests_title_trgm_idx on public.feature_requests using gin (title gin_trgm_ops);
create index feature_requests_status_idx on public.feature_requests (status);
create index feature_requests_category_idx on public.feature_requests (category);
create index feature_requests_listing_idx on public.feature_requests (is_pinned desc, upvote_count desc);

-- Reuses the shared public.touch_updated_at() already defined by the main app's
-- migrations (supabase/migrations/20260708102734_phase1_core_schema.sql) — not
-- redefined here, just referenced by name.
create trigger trg_feature_requests_touch before update on public.feature_requests
  for each row execute function public.touch_updated_at();

alter table public.feature_requests enable row level security;

create policy "feature_requests_select_all" on public.feature_requests
  for select using (true);

create policy "feature_requests_insert_own" on public.feature_requests
  for insert with check (author_id = auth.uid());

-- Owner can edit their own request only within 15 minutes of creation; the trigger
-- below additionally restricts *which columns* a non-admin edit may touch (RLS can
-- gate rows, not columns).
create policy "feature_requests_update_own_recent" on public.feature_requests
  for update
  using (author_id = auth.uid() and created_at > now() - interval '15 minutes')
  with check (author_id = auth.uid());

create policy "feature_requests_update_admin" on public.feature_requests
  for update using (public.is_feedback_admin()) with check (public.is_feedback_admin());

create policy "feature_requests_delete_admin" on public.feature_requests
  for delete using (public.is_feedback_admin());

-- RLS can restrict *which rows* a non-admin may update (own request, within 15
-- minutes), but not *which columns* — this trigger enforces that a non-admin editor
-- may only change title/description/category, never status/pin/merge/author/slug/counts.
-- Admins are exempt (checked first) since they legitimately need to change all of those.
create or replace function public.enforce_feature_request_owner_edit_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_feedback_admin() then
    return new;
  end if;

  if new.status is distinct from old.status
    or new.is_pinned is distinct from old.is_pinned
    or new.merged_into is distinct from old.merged_into
    or new.author_id is distinct from old.author_id
    or new.slug is distinct from old.slug
    or new.upvote_count is distinct from old.upvote_count
    or new.comment_count is distinct from old.comment_count
  then
    raise exception 'Only admins can change status, pin, merge, author, slug, or counts on a feature request.';
  end if;

  return new;
end;
$$;

create trigger trg_feature_requests_owner_edit_scope
  before update on public.feature_requests
  for each row execute function public.enforce_feature_request_owner_edit_scope();
