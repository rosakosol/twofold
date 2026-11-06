-- MFA for the console, stage 2 of 2: an admin's powers need an aal2 session.
--
-- ===========================================================================
-- DO NOT PUSH THIS UNTIL EVERY ADMIN HAS A VERIFIED FACTOR.
-- ===========================================================================
--
-- This file lives in supabase/pending/ so that `db push` cannot pick it up. supabase/pending/README.md
-- has the rollout and the command that moves it into migrations/.
--
-- Check first, in the SQL Editor. Every row must say true:
--
--   select fa.role, u.email,
--          exists (select 1 from auth.mfa_factors f
--                  where f.user_id = fa.profile_id
--                    and f.status = 'verified' and f.factor_type = 'totp') as has_mfa
--   from public.feedback_admins fa
--   join auth.users u on u.id = fa.profile_id
--   order by 2, 1;
--
-- The block below refuses to apply if any row would say false, so a mistimed push fails rather than
-- locks somebody out. It cannot tell whether that person still has their authenticator. That holds
-- for `db push`, which stops at the error. Don't apply this with plain psql, which carries on to the
-- next statement unless told `ON_ERROR_STOP`.
--
-- ---------------------------------------------------------------------------
-- If somebody is locked out
-- ---------------------------------------------------------------------------
--
-- The SQL Editor has no `auth.jwt()`, so nothing here applies to it. Either of these, there:
--
-- 1. Remove the lost factor. The admin signs in with their password and the console takes them to
--    enrol again, which needs no aal2 for a person with no verified factor.
--
--      delete from auth.mfa_factors
--      where user_id = (select id from auth.users where email = 'THE_ADMIN@EXAMPLE.COM');
--
--    If the authenticator may be in someone else's hands, end that account's sessions too, because
--    an aal2 session outlives its factor:
--
--      delete from auth.sessions
--      where user_id = (select id from auth.users where email = 'THE_ADMIN@EXAMPLE.COM');
--
-- 2. Turn enforcement off for everyone. The helper is the only thing this file adds to the checks, so
--    this restores the behaviour from before it at once. The console notices by itself and goes back
--    to the enrol banner.
--
--      create or replace function private.admin_session_has_mfa()
--      returns boolean language sql stable set search_path = '' as $fn$ select true; $fn$;
--
-- ---------------------------------------------------------------------------
-- Who each check answers for
-- ---------------------------------------------------------------------------
--
-- A signed-in user's JWT needs aal2. Everything else is exactly as before: the service role (which
-- acts for a named, already-checked actor in `admin_scrub_account`), anon, cron and the SQL Editor all
-- have no `auth.uid()`, so the helper says true and the roster lookup decides. With the default
-- argument that lookup is against null and finds nothing; with an explicit id it answers as it
-- always did.
--
-- Keyed on `auth.uid()` rather than on `auth.jwt()` being present, so that a user with no readable
-- claims is refused rather than waved through. A missing `aal` is refused for the same reason.
--
-- Everything that calls these inherits it, which is the point of doing it here: the RLS policies,
-- every admin_* and api_usage_* function, and the admin-actions, send-support-reply and
-- support-attachment-upload functions, which all ask under the caller's own JWT.
--
-- Read-only check once applied:
--
--   select pg_get_functiondef('public.is_support_admin(uuid)'::regprocedure);  -- has the helper
--   select public.is_support_admin('AN_ADMIN_UUID');                           -- SQL Editor: true
--
-- Then in the browser: the console opens at aal2, and a fresh sign-in asks for a code before it
-- shows anything.

do $$
declare
  v_missing text;
begin
  select string_agg(distinct u.email, ', ') into v_missing
  from public.feedback_admins fa
  join auth.users u on u.id = fa.profile_id
  where not exists (
    select 1 from auth.mfa_factors f
    where f.user_id = fa.profile_id and f.status = 'verified' and f.factor_type = 'totp'
  );

  if v_missing is not null then
    raise exception 'Not applying MFA enforcement: no verified factor for %', v_missing;
  end if;
end $$;

create or replace function private.admin_session_has_mfa()
returns boolean
language sql
stable
set search_path = ''
as $$
  select case
    when auth.role() = 'service_role' then true
    when auth.uid() is null then true
    else coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
  end;
$$;

comment on function private.admin_session_has_mfa() is
  'False only for a signed-in user whose JWT is not aal2. The is_*_admin() functions AND this with '
  'their roster lookup. Their SECURITY DEFINER is what lets them reach it: clients have no usage on '
  'the private schema.';

revoke all on function private.admin_session_has_mfa() from public, anon, authenticated;

-- Signatures, SECURITY DEFINER and search_path as before, and `create or replace` keeps the grants
-- from 20261110000300.
create or replace function public.is_feedback_admin(check_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select private.admin_session_has_mfa() and exists (
    select 1 from public.feedback_admins
    where profile_id = check_id and role = 'content'
  );
$$;

create or replace function public.is_support_admin(check_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select private.admin_session_has_mfa() and exists (
    select 1 from public.feedback_admins
    where profile_id = check_id and role = 'support'
  );
$$;

create or replace function public.is_billing_admin(check_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select private.admin_session_has_mfa() and exists (
    select 1 from public.feedback_admins
    where profile_id = check_id and role = 'billing'
  );
$$;

create or replace function public.is_console_admin(check_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select private.admin_session_has_mfa() and exists (
    select 1 from public.feedback_admins where profile_id = check_id
  );
$$;
