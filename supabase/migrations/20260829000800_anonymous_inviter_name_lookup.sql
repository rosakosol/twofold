-- get_invite_code_inviter_name required authentication, but the one place its real value
-- matters most — JoinInviteView, "{name} invited you to Twofold" (now also showing their
-- avatar) — is reached from a cold deep-link tap, before any account/session exists. It was
-- silently always falling back to generic copy there, a real regression from the old
-- (guessable, since fixed) code-prefix scheme, which at least worked pre-auth.
--
-- Reveals only a first name + avatar for a still-pending code, the same low-sensitivity
-- information a real invite link/email would already show. Since an anonymous caller has no
-- stable auth.uid() to rate-limit by, this switches to a per-*code* cap instead of per-caller —
-- bounds how many times any single code's info can be hammered, though not how many different
-- codes an anonymous prober tries. That's an acceptable trade: the actual security-sensitive
-- operation (redemption, and creating a connection request from it) still requires real
-- authentication and keeps its own per-caller rate limit untouched.

alter table public.invite_codes
  add column name_lookup_count int not null default 0;

drop function if exists public.get_invite_code_inviter_name(text);

create or replace function public.get_invite_code_inviter_info(p_code text)
returns table (first_name text, avatar_path text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_first_name text;
  v_avatar_path text;
  v_count int;
begin
  select p.first_name, p.avatar_path, i.name_lookup_count
  into v_first_name, v_avatar_path, v_count
  from public.invite_codes i
  join public.profiles p on p.id = i.inviter_id
  where i.code = upper(trim(p_code)) and i.status = 'pending' and i.expires_at > now();

  if v_first_name is null then
    return;
  end if;

  if v_count >= 20 then
    raise exception 'Too many attempts for this code — please wait a while before trying again.';
  end if;

  update public.invite_codes
  set name_lookup_count = name_lookup_count + 1
  where code = upper(trim(p_code));

  return query select v_first_name, v_avatar_path;
end;
$$;

revoke all on function public.get_invite_code_inviter_info(text) from public;
grant execute on function public.get_invite_code_inviter_info(text) to anon, authenticated;
