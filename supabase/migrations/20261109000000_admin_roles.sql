-- ---------------------------------------------------------------------------
-- One admin roster, three kinds of admin
-- ---------------------------------------------------------------------------
--
-- `feedback_admins` has meant exactly one thing since 20260830000850: may write game content and
-- FAQ entries. The admin console now needs two more powers that are not that one --
--
--   * support -- read another person's account, delete it, dissolve their couple, act on their
--     subscription. This is the only role that touches personal data.
--   * billing -- read AeroAPI usage and spend. Business-sensitive, but no personal data in it at
--     all, which is why it is deliberately NOT folded into `support`: gating a cost dashboard
--     behind the most privileged role is backwards, and it would mean anyone who should see the
--     bill must also be trusted to delete accounts.
--
-- ---------------------------------------------------------------------------
-- Why a composite key rather than a role column
-- ---------------------------------------------------------------------------
--
-- The obvious move is `add column role` on a table keyed by `profile_id`, which quietly means one
-- role per person. Today that breaks immediately: the only admin needs all three. So the key
-- becomes `(profile_id, role)` and a person holds one row per role they have.
--
-- ---------------------------------------------------------------------------
-- Why production does not change behaviour
-- ---------------------------------------------------------------------------
--
-- `is_feedback_admin()` is referenced by roughly fifteen policy clauses across five migrations
-- (game_decks, game content tables, duplicate dismissals, faq_entries, daily_questions) plus the
-- guard inside `delete_game_deck`. Every one of them means "may write content".
--
-- So: the column defaults to 'content', which is what every existing row becomes, and
-- `is_feedback_admin()` is narrowed to test `role = 'content'` rather than mere presence. For the
-- rows that exist today those two statements are identical, and no policy changes meaning. What
-- the narrowing buys is that a future billing-only admin does not silently inherit content write
-- access from an `exists (select 1 ...)` that never looked at the role.
--
-- Idempotent throughout -- the table already exists in production and this file has to be safe to
-- apply there, and safe to re-apply to an environment that has already had it.

alter table public.feedback_admins
  add column if not exists role text not null default 'content';

-- Separate from the column add so re-running finds the constraint already present rather than
-- failing on a duplicate name.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.feedback_admins'::regclass
      and conname = 'feedback_admins_role_check'
  ) then
    alter table public.feedback_admins
      add constraint feedback_admins_role_check check (role in ('content', 'support', 'billing'));
  end if;
end
$$;

-- profile_id -> (profile_id, role). Nothing references this table by foreign key, so the primary
-- key can be swapped without touching anything else.
do $$
begin
  if exists (
    select 1 from pg_constraint
    where conrelid = 'public.feedback_admins'::regclass
      and conname = 'feedback_admins_pkey'
      and array_length(conkey, 1) = 1
  ) then
    alter table public.feedback_admins drop constraint feedback_admins_pkey;
    alter table public.feedback_admins add constraint feedback_admins_pkey primary key (profile_id, role);
  end if;
end
$$;

comment on column public.feedback_admins.role is
  'What this row grants. content = write game content and FAQ entries (the original and only '
  'meaning of this table). support = read and act on another person''s account. billing = read '
  'API usage and spend. One row per role held; a person with all three has three rows.';

-- Narrowed to 'content'. Every row that existed before this migration has role = 'content', so
-- this returns exactly what it returned yesterday for everyone currently in the table.
create or replace function public.is_feedback_admin(check_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.feedback_admins
    where profile_id = check_id and role = 'content'
  );
$$;

-- May read and act on another person's account. Every function gated on this one writes an audit
-- row; see the admin console's own migrations.
create or replace function public.is_support_admin(check_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.feedback_admins
    where profile_id = check_id and role = 'support'
  );
$$;

-- May read API usage and spend. No personal data sits behind this gate.
create or replace function public.is_billing_admin(check_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.feedback_admins
    where profile_id = check_id and role = 'billing'
  );
$$;

grant execute on function public.is_support_admin(uuid) to authenticated;
grant execute on function public.is_billing_admin(uuid) to authenticated;
