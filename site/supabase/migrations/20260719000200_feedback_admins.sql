-- Feedback board admin flags. A brand-new, standalone table — deliberately not an
-- `is_admin` column bolted onto the shared `public.profiles` table, to avoid any
-- ALTER TABLE on a table the main app (and any concurrent work on it) owns.
--
-- There is no client-facing way to grant admin — bootstrap the first admin manually:
--   insert into public.feedback_admins (profile_id) values ('<your-profile-uuid>');
-- run once via the Supabase SQL editor, then admins can be added by existing admins
-- through the /admin UI once Phase 7 lands (still just inserting into this table).

create table public.feedback_admins (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.feedback_admins enable row level security;

-- Admins can see the list of admins (used by the admin UI); nobody else can, and
-- nobody can write to this table via the API at all — it's SQL-editor-only by design.
create policy "feedback_admins_select_own_or_admin" on public.feedback_admins
  for select using (
    profile_id = auth.uid()
    or exists (select 1 from public.feedback_admins fa where fa.profile_id = auth.uid())
  );

-- Mirrors the existing is_couple_member/is_couple_active pattern (see
-- supabase/migrations/20260708102734_phase1_core_schema.sql) — a security-definer
-- helper used inside other tables' RLS policies, rather than repeating the exists()
-- check inline everywhere.
create or replace function public.is_feedback_admin(check_id uuid default auth.uid())
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.feedback_admins where profile_id = check_id
  );
$$;

grant execute on function public.is_feedback_admin(uuid) to anon, authenticated;
