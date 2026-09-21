-- ---------------------------------------------------------------------------
-- Deleting an account from the console never worked
-- ---------------------------------------------------------------------------
--
-- `admin_scrub_account` gates on `is_support_admin()`, which reads `auth.uid()`. The `admin-actions`
-- edge function calls it with the SERVICE client — where `auth.uid()` is null — so the check failed
-- and every deletion raised 42501 before touching anything. The console reported "check the logs"
-- and nothing had happened.
--
-- The comment in that function said the check "passes trivially" for the service role. It does the
-- opposite, and nothing caught it: the pgTAP test exercised the function as a support admin and as
-- a content admin, which are the two paths the edge function does NOT take. A gate tested only
-- through the door nobody uses is untested.
--
-- ---------------------------------------------------------------------------
-- Two callers, two ways of being authorised
-- ---------------------------------------------------------------------------
--
-- A browser caller proves who it is with a JWT, and `auth.uid()` is the answer. The edge function
-- cannot: it holds the service key precisely because it needs to do things a user cannot, and it
-- has already verified the caller's role itself, with the caller's own client, before getting here.
--
-- So the service role is accepted as pre-authorised — and made to say who it is acting for. The
-- actor is not optional there: the whole value of the audit row is that it names a person, and a
-- deletion attributed to "the service role" names nobody. This is the same shape
-- `admin_record_action` already uses, and for the same reason.
--
-- `auth.role()`, NOT `current_user`. Inside a `security definer` function `current_user` is the
-- function's OWNER, so it reports `postgres` for every caller and the branch never fires — which is
-- the second half of this same bug, found while fixing the first. 20260915000000 documents the trap
-- exactly: "a security definer function would report its owner instead, making every caller look
-- trusted", which is why that trigger is deliberately not a definer.
--
-- `auth.role()` reads the `role` claim out of the request JWT, so it describes the caller and
-- survives the definer boundary. A caller cannot choose it — Supabase sets it from the key used,
-- and PostgREST refuses a token claiming a role its authenticator is not a member of.
--
-- Anything reaching this as `authenticated` still has to be a support admin, so the browser path is
-- unchanged.

create or replace function public.admin_scrub_account(
  p_profile_id uuid,
  p_reason text,
  p_actor uuid default null
)
returns void
language plpgsql
security definer
set search_path = private, public, auth
as $$
declare
  v_actor uuid;
begin
  if auth.role() = 'service_role' then
    -- Pre-authorised by `admin-actions`, which checked is_support_admin() against the caller's own
    -- JWT before reaching for the service key.
    if p_actor is null then
      raise exception 'an actor is required when called as the service role' using errcode = '22023';
    end if;
    v_actor := p_actor;
  else
    if not public.is_support_admin() then
      raise exception 'not authorised' using errcode = '42501';
    end if;
    v_actor := auth.uid();
  end if;

  if coalesce(trim(p_reason), '') = '' then
    raise exception 'a reason is required' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_profile_id) then
    raise exception 'no such account';
  end if;

  perform private.scrub_account(p_profile_id);

  -- Written directly rather than through `private.record_admin_action`, which reads auth.uid() and
  -- would attribute a service-role deletion to nobody — the same null that caused this bug.
  insert into private.admin_audit_log (actor_id, action, subject_profile_id, reason, details)
  values (v_actor, 'account.scrub', p_profile_id, p_reason, null);
end;
$$;

revoke execute on function public.admin_scrub_account(uuid, text, uuid) from anon;
grant execute on function public.admin_scrub_account(uuid, text, uuid) to authenticated, service_role;

-- The two-argument form is gone: leaving it would mean the edge function could still call the
-- broken one by passing no actor, which is exactly the shape of the bug.
drop function if exists public.admin_scrub_account(uuid, text);
