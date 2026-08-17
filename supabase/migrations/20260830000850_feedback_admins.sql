-- Captures `feedback_admins` + `is_feedback_admin()` in source control.
--
-- Both were created directly against production by the feedback app (site/feedback/) and never
-- written down here, which is why `supabase db reset` has been unusable: the very next migration,
-- 20260830000900_game_content_admin_write.sql, builds RLS policies on top of `is_feedback_admin()`
-- and dies with "function public.is_feedback_admin() does not exist" against a fresh database.
-- Anything that starts from zero — a local reset, a CI run, a staging project — hit the same wall.
--
-- Dated 20260830000850 so it lands immediately before the migration that first needs it. Production
-- already has both objects, so this file must NOT re-run there; it is marked applied out of band
-- with `supabase migration repair --status applied 20260830000850`. Every statement is written
-- idempotently anyway, so applying it to an environment that already has these objects is a no-op
-- rather than an error.
--
-- Definitions mirror what production actually has today (read back via pg_get_functiondef,
-- pg_policies and pg_constraint) rather than what we might design fresh — the point is to make a
-- reset reproduce production, not to redesign it.

create table if not exists public.feedback_admins (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.feedback_admins enable row level security;

-- Admins can see the whole roster; everyone else can only confirm their own (non-)membership,
-- which is what the feedback app's client-side admin check reads.
drop policy if exists "feedback_admins_select_own_or_admin" on public.feedback_admins;
create policy "feedback_admins_select_own_or_admin" on public.feedback_admins
  for select to authenticated
  using (
    profile_id = auth.uid()
    or exists (select 1 from public.feedback_admins fa where fa.profile_id = auth.uid())
  );

-- security definer so the RLS policies that call it (see 20260830000900) can read the roster
-- without recursing back through this table's own select policy.
create or replace function public.is_feedback_admin(check_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.feedback_admins where profile_id = check_id
  );
$$;

grant select on public.feedback_admins to authenticated;
grant execute on function public.is_feedback_admin(uuid) to authenticated;
