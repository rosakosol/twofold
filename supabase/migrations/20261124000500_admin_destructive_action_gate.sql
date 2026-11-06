-- Destructive console actions are decided by the server, not the dialog (security review, F9).
--
-- The typed confirmation lived only in the browser. With a stolen session, a script could delete
-- every account in a loop, including other admins. MFA (20261124000200) proves a code was entered at
-- some point in the session, which can be days ago and survives every token refresh.
--
-- Now, before deleting an account, disconnecting a couple, cancelling a subscription or purging an
-- archive, the database requires:
--
--   * A code entered in the last 5 minutes. This is the real protection: a stolen token or refresh
--     token keeps the time of the last code, and cannot get a newer one without the authenticator.
--   * The confirmation the dialog asks for. Somebody with a session can look the value up, so this
--     stops mistakes and blind loops, not a determined attacker.
--   * 10 such actions an hour and 30 a day, per admin, which limits what a fresh code can do.
--     To change them, replace private.admin_destructive_gate in a new migration.
--   * A target that is not an admin. Remove the role first, which takes database access:
--       delete from public.feedback_admins where profile_id = '...';
--
-- A password reset email is not included. It destroys nothing and can only go to the account's own
-- address.
--
-- admin_scrub_account also stops being callable by a signed-in user. Its only real caller is
-- admin-actions with the service key, which asks admin_authorize_account_action first.

create or replace function private.admin_destructive_gate(p_subject uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_retry integer;
begin
  if not exists (
    select 1
    from jsonb_array_elements(
      case when jsonb_typeof(auth.jwt() -> 'amr') = 'array' then auth.jwt() -> 'amr' else '[]'::jsonb end
    ) as entry
    where entry ->> 'method' = 'totp'
      and (entry ->> 'timestamp')::bigint > extract(epoch from now()) - 300
  ) then
    raise exception 'Enter a current authenticator code to do this.' using errcode = '42501';
  end if;

  if length(trim(coalesce(p_reason, ''))) < 3 then
    raise exception 'a reason is required' using errcode = '22023';
  end if;
  if length(p_reason) > 500 then
    raise exception 'That reason is too long.' using errcode = '22023';
  end if;

  if p_subject is not null and exists (select 1 from public.feedback_admins where profile_id = p_subject) then
    raise exception 'This account is an admin. Remove its admin role before doing this.' using errcode = '42501';
  end if;

  select retry_after_seconds into v_retry
  from public.consume_rate_limit('admin_destructive_hour', 10, interval '1 hour')
  where not allowed;
  if v_retry is null then
    select retry_after_seconds into v_retry
    from public.consume_rate_limit('admin_destructive_day', 30, interval '1 day')
    where not allowed;
  end if;
  if v_retry is not null then
    raise exception 'You have reached the limit for destructive actions. Try again in % minutes.',
      ceil(v_retry / 60.0)::integer
      using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function private.admin_destructive_gate(uuid, text) from public, anon, authenticated;

-- Exact match first, because the database and the browser can lower-case some letters differently.
create or replace function private.admin_confirmation_matches(p_typed text, p_expected text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select trim(coalesce(p_typed, '')) <> ''
    and (trim(p_typed) = trim(p_expected) or lower(trim(p_typed)) = lower(trim(p_expected)));
$$;

revoke all on function private.admin_confirmation_matches(text, text) from public, anon, authenticated;

-- What admin-actions asks, as the caller, before it uses the service key. The confirmation for a
-- deletion is the account's email, or its id if it has none. Cancelling a subscription refunds and
-- deletes nothing, so its dialog has no typed confirmation.
create or replace function public.admin_authorize_account_action(
  p_action text,
  p_profile_id uuid,
  p_reason text,
  p_confirmation text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text;
begin
  if not public.is_support_admin() then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  if p_action not in ('account.delete', 'subscription.cancel') then
    raise exception 'Unknown action' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_profile_id) then
    raise exception 'no such account' using errcode = '22023';
  end if;

  if p_action = 'account.delete' then
    select u.email::text into v_email from auth.users u where u.id = p_profile_id;
    if not private.admin_confirmation_matches(
      p_confirmation, coalesce(nullif(trim(v_email), ''), p_profile_id::text)
    ) then
      raise exception 'That confirmation does not match this account.' using errcode = '22023';
    end if;
  end if;

  perform private.admin_destructive_gate(p_profile_id, p_reason);
end;
$$;

revoke all on function public.admin_authorize_account_action(text, uuid, text, text) from public, anon;
grant execute on function public.admin_authorize_account_action(text, uuid, text, text) to authenticated;

-- A new signature, so the version that takes no confirmation cannot still be called.
drop function if exists public.admin_dissolve_couple(uuid, uuid, text);

-- The confirmation is the partner's first name, or the start of the couple's id if they have none.
create function public.admin_dissolve_couple(
  p_couple_id uuid,
  p_on_behalf_of uuid,
  p_reason text,
  p_confirmation text
)
returns public.couples
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_couple public.couples;
  v_partner_id uuid;
  v_partner_name text;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  select * into v_couple from public.couples where id = p_couple_id;
  if not found then
    raise exception 'Couple not found';
  end if;
  if v_couple.partner_a_id <> p_on_behalf_of and v_couple.partner_b_id <> p_on_behalf_of then
    raise exception 'That profile is not a member of this couple';
  end if;
  v_partner_id := case when v_couple.partner_a_id = p_on_behalf_of then v_couple.partner_b_id else v_couple.partner_a_id end;

  select first_name into v_partner_name from public.profiles where id = v_partner_id;
  if not private.admin_confirmation_matches(
    p_confirmation, coalesce(nullif(trim(v_partner_name), ''), left(p_couple_id::text, 8))
  ) then
    raise exception 'That confirmation does not match this couple.' using errcode = '22023';
  end if;

  perform private.admin_destructive_gate(p_on_behalf_of, p_reason);

  v_couple := private.dissolve_couple(p_couple_id, p_on_behalf_of);

  perform private.record_admin_action(
    'couple.dissolve', p_on_behalf_of, p_reason,
    jsonb_build_object('couple_id', p_couple_id, 'partner_id', v_partner_id)
  );

  return v_couple;
end;
$$;

revoke all on function public.admin_dissolve_couple(uuid, uuid, text, text) from public, anon;
grant execute on function public.admin_dissolve_couple(uuid, uuid, text, text) to authenticated;

drop function if exists public.admin_purge_couple_archive(uuid, text);

-- Both partners are deleted by the time this runs, so their names are gone and the confirmation is
-- the start of the couple's id. Neither is on the roster any more, so no subject is passed.
create function public.admin_purge_couple_archive(p_couple_id uuid, p_reason text, p_confirmation text)
returns void
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_couple public.couples;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  if not private.admin_confirmation_matches(p_confirmation, left(p_couple_id::text, 8)) then
    raise exception 'That confirmation does not match this couple.' using errcode = '22023';
  end if;

  select * into v_couple from public.couples where id = p_couple_id for update;
  if not found then
    raise exception 'no such couple';
  end if;
  if v_couple.status <> 'dissolved' then
    raise exception 'only an archived couple can be purged' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.profiles
    where id in (v_couple.partner_a_id, v_couple.partner_b_id)
      and account_deleted_at is null
  ) then
    raise exception 'both partners must have deleted their accounts; otherwise the archive waits for its timer'
      using errcode = '22023';
  end if;

  perform private.admin_destructive_gate(null, p_reason);

  perform public.purge_couple_data(p_couple_id);

  perform private.record_admin_action(
    'couple.purge', v_couple.partner_a_id, p_reason,
    jsonb_build_object('couple_id', p_couple_id, 'partner_id', v_couple.partner_b_id,
                       'scheduled_purge_at', v_couple.scheduled_purge_at)
  );
  perform private.record_admin_action(
    'couple.purge', v_couple.partner_b_id, p_reason,
    jsonb_build_object('couple_id', p_couple_id, 'partner_id', v_couple.partner_a_id,
                       'scheduled_purge_at', v_couple.scheduled_purge_at)
  );
end;
$$;

revoke all on function public.admin_purge_couple_archive(uuid, text, text) from public, anon;
grant execute on function public.admin_purge_couple_archive(uuid, text, text) to authenticated;

revoke all on function public.admin_scrub_account(uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.admin_scrub_account(uuid, text, uuid) to service_role;
