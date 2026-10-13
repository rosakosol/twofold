-- ---------------------------------------------------------------------------
-- Sending somebody a password reset email from the console
-- ---------------------------------------------------------------------------
--
-- Support's most common "I can't get in" answer is "use Forgot password", and the person on the
-- other end of the email has often already tried and lost the message, or is not sure which address
-- the account is under. This lets the console send the same standard recovery email for them.
--
-- The console never sees or sets a password, and there is no temporary password and no copyable
-- link: the email goes to the address on the account and nowhere else, and the person chooses the
-- new password themselves at /auth/reset-password, exactly as if they had asked.
--
-- Why a function and not just the client calling resetPasswordForEmail
-- ---------------------------------------------------------------------------
--
-- The send itself is the public `/recover` endpoint, which needs no service key, so unlike
-- `account.delete` it does not belong in the admin-actions edge function. What this function is
-- for is the two things the browser must not decide:
--
--   * WHERE it goes. The address is read from auth.users here and returned, so a console caller
--     cannot aim a recovery email at an arbitrary address by passing one in.
--   * THAT it was done. The audit row is written before the address is handed back, so there is
--     no way to get the address for a send without leaving the entry.
--
-- The consequence is that the entry means "requested", not "delivered": the console sends after
-- this returns, and Supabase can still refuse (it rate-limits recovery to about one a minute per
-- address). The console says so when that happens, and the entry stays, which is the honest record
-- of what an admin did.
--
-- An account with no email identity (Apple or Google only) has no password to reset, and choosing
-- one through the link ADDS a password to it. That is what anybody could do from the public
-- "Forgot password?" form, so it is allowed, but only when the caller says it knows:
-- `p_acknowledge_adds_password`. The console asks for that as a tick box; checked here as well so a
-- hand-built call cannot skip it.

create or replace function public.admin_prepare_password_reset(
  p_profile_id uuid,
  p_reason text,
  p_acknowledge_adds_password boolean default false
)
returns text
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_email text;
  v_auth_deleted_at timestamptz;
  v_profile_deleted_at timestamptz;
  v_providers text[];
  v_has_email_identity boolean;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'a reason is required' using errcode = '22023';
  end if;

  select u.email::text, u.deleted_at
    into v_email, v_auth_deleted_at
  from auth.users u
  where u.id = p_profile_id;
  if not found then
    raise exception 'no such account';
  end if;

  select p.account_deleted_at into v_profile_deleted_at
  from public.profiles p
  where p.id = p_profile_id;

  -- Either half of a deletion is enough: sign-in is disabled for good, so a reset would only send a
  -- link that cannot work to an address that may no longer be theirs.
  if v_auth_deleted_at is not null or v_profile_deleted_at is not null then
    raise exception 'this account has been deleted, so there is no password to reset' using errcode = '22023';
  end if;
  if coalesce(trim(v_email), '') = '' then
    raise exception 'this account has no email address to send a reset to' using errcode = '22023';
  end if;

  select coalesce(array_agg(distinct i.provider order by i.provider), '{}')
    into v_providers
  from auth.identities i
  where i.user_id = p_profile_id;
  v_has_email_identity := 'email' = any(v_providers);

  if not v_has_email_identity and not coalesce(p_acknowledge_adds_password, false) then
    raise exception 'this account has no password; confirm that a reset would add one' using errcode = '22023';
  end if;

  -- The address at the time, because it can change later and "sent to whom" is the question the
  -- entry exists to answer.
  perform private.record_admin_action(
    'account.password_reset', p_profile_id, p_reason,
    jsonb_build_object(
      'email', v_email,
      'providers', to_jsonb(v_providers),
      'adds_password', not v_has_email_identity
    )
  );

  return v_email;
end;
$$;

revoke all on function public.admin_prepare_password_reset(uuid, text, boolean) from public, anon;
grant execute on function public.admin_prepare_password_reset(uuid, text, boolean) to authenticated;
