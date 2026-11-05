-- MFA for the console, stage 1 of 2: what the console needs to know. Changes no permission.
--
-- A phished password should not be enough to act as an admin (security review, F1). The end state is
-- that every `is_*_admin()` needs an aal2 session, but that cannot go live until the admins have
-- enrolled, and enrolling happens in the console. So this stage only lets the console ask where the
-- caller stands; the enforcement is `supabase/pending/admin_mfa_enforcement.sql`, pushed by hand
-- later. See `supabase/pending/README.md` for the order.
--
-- ---------------------------------------------------------------------------
-- my_console_access()
-- ---------------------------------------------------------------------------
--
-- Once enforcement is on, `is_console_admin()` answers false for an admin at aal1, exactly as it does
-- for a stranger. The console has to tell those two apart or an admin who has merely not done their
-- second step looks like someone who lost their role. So `is_admin` reads the roster directly, and is
-- for routing only: nothing may authorise from it, and it says nothing a caller could not already
-- read, since `feedback_admins` lets a person select their own rows.
--
-- `data_gate_open` is the data gate's own answer, and the reason the site does not need a code change
-- between the stages. It is true for an admin at aal1 today and false the moment enforcement lands,
-- so the console is reading what the database actually does rather than a flag that could disagree
-- with it.
--
-- `aal` comes from the JWT that PostgREST has already verified, so the layout needs no decode of its
-- own and nothing in a cookie is trusted. No argument on purpose: this can only be about the caller.
create or replace function public.my_console_access()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'is_admin', exists (select 1 from public.feedback_admins where profile_id = auth.uid()),
    'aal', coalesce(auth.jwt() ->> 'aal', 'aal1'),
    'has_verified_factor', exists (
      select 1 from auth.mfa_factors
      where user_id = auth.uid() and status = 'verified' and factor_type = 'totp'
    ),
    'data_gate_open', public.is_console_admin()
  );
$$;

comment on function public.my_console_access() is
  'Where the calling session stands at the console door: {is_admin, aal, has_verified_factor, '
  'data_gate_open}. is_admin ignores assurance level and is for routing only; the data gates are '
  'the is_*_admin() functions.';

revoke all on function public.my_console_access() from public, anon;
grant execute on function public.my_console_access() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- my_admin_roles() gains `member`
-- ---------------------------------------------------------------------------
--
-- The three roles here go through the gated functions and rightly so: they decide which console tabs
-- show. But the public site's header also uses this to show the door to the console, and that door
-- has to stay visible to an admin at aal1, who needs it to go and do their second step. `member` is
-- the roster read for that one link. It unlocks nothing, and this function is still callable by anon,
-- who gets false because `auth.uid()` is null.
create or replace function public.my_admin_roles()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'content', public.is_feedback_admin(),
    'support', public.is_support_admin(),
    'billing', public.is_billing_admin(),
    'member', exists (select 1 from public.feedback_admins where profile_id = auth.uid())
  );
$$;

comment on function public.my_admin_roles() is
  'Every admin role the calling session holds, as {content, support, billing}, plus member: on the '
  'admin roster at all, whatever the session''s assurance level. For a client deciding what to '
  'render; SQL gates keep using the individual is_*_admin() functions. Returns all false for an '
  'anonymous caller rather than raising, which is what lets the client ask without first waiting to '
  'find out whether it has a session.';
