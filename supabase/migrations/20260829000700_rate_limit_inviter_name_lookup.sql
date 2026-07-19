-- get_invite_code_inviter_name (previous migration) was a free, side-effect-free lookup with no
-- rate limiting of its own — cheaper to brute-force through than redeem_invite_code itself, since
-- it has no risk of an unwanted connection_request as a side effect to weigh against spamming it.
-- Shares the same attempt budget as redeem_invite_code (both count as "probing a code").
--
-- Bumped the shared threshold from 5 to 10 per 15 minutes while here: the real client flow now
-- calls this lookup *then* redeem_invite_code for a single "Connect" tap (to show "request sent
-- to {name}"), which would otherwise burn through the original 5-attempt budget twice as fast
-- for a normal user typing their own partner's code correctly on the first try.

create or replace function public.get_invite_code_inviter_name(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
  v_recent_attempts int;
  v_name text;
begin
  if v_caller_id is null then
    raise exception 'Not authenticated';
  end if;

  select count(*) into v_recent_attempts
  from public.invite_redemption_attempts
  where redeemer_id = v_caller_id and attempted_at > now() - interval '15 minutes';

  if v_recent_attempts >= 10 then
    raise exception 'Too many attempts — please wait a while before trying again.';
  end if;

  insert into public.invite_redemption_attempts (redeemer_id) values (v_caller_id);

  select p.first_name into v_name
  from public.invite_codes i
  join public.profiles p on p.id = i.inviter_id
  where i.code = upper(trim(p_code)) and i.status = 'pending' and i.expires_at > now();

  return v_name;
end;
$$;

create or replace function public.redeem_invite_code(p_code text)
returns public.connection_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.invite_codes;
  v_redeemer_id uuid := auth.uid();
  v_recent_attempts int;
  v_request public.connection_requests;
begin
  if v_redeemer_id is null then
    raise exception 'Not authenticated';
  end if;

  select count(*) into v_recent_attempts
  from public.invite_redemption_attempts
  where redeemer_id = v_redeemer_id and attempted_at > now() - interval '15 minutes';

  if v_recent_attempts >= 10 then
    raise exception 'Too many attempts — please wait a while before trying again.';
  end if;

  insert into public.invite_redemption_attempts (redeemer_id) values (v_redeemer_id);

  select * into v_invite
  from public.invite_codes
  where code = upper(trim(p_code))
  for update;

  if not found then
    raise exception 'Invite code not found';
  end if;

  if v_invite.status <> 'pending' then
    raise exception 'Invite code is no longer valid';
  end if;

  if v_invite.expires_at < now() then
    update public.invite_codes set status = 'expired' where code = v_invite.code;
    raise exception 'Invite code has expired';
  end if;

  if v_invite.inviter_id = v_redeemer_id then
    raise exception 'You cannot redeem your own invite code';
  end if;

  if exists (
    select 1 from public.couples
    where (partner_a_id = v_redeemer_id or partner_b_id = v_redeemer_id) and status = 'active'
  ) then
    raise exception 'You are already connected with a partner';
  end if;

  update public.invite_codes
  set status = 'redeemed', redeemed_at = now()
  where code = v_invite.code;

  insert into public.connection_requests (invite_code, inviter_id, requester_id)
  values (v_invite.code, v_invite.inviter_id, v_redeemer_id)
  returning * into v_request;

  return v_request;
end;
$$;
