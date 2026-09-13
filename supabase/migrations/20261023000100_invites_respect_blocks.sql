-- ---------------------------------------------------------------------------
-- A block stops an invite code working
-- ---------------------------------------------------------------------------
--
-- `blocked_profiles` (20261023000000) is only a record until something consults it. This is the
-- place that matters: redeeming a code is how one person reaches another, and it is the path a
-- blocked person would use to come back.
--
-- The whole function is restated rather than patched, because it is `security definer` and its
-- last definition lives in 20261008000000 — a partial redefinition would silently drop the
-- auto-accept behaviour that migration added. Only the block check below is new; everything else
-- is carried over verbatim.

create or replace function public.redeem_invite_code(
  p_code text,
  p_origin public.connection_request_origin default 'code'
)
returns table (id uuid, inviter_id uuid, error_message text, auto_accepted boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.invite_codes;
  v_redeemer_id uuid := auth.uid();
  v_recent_attempts int;
  v_request public.connection_requests;
  v_auto boolean := false;
begin
  if v_redeemer_id is null then
    raise exception 'Not authenticated';
  end if;

  select count(*) into v_recent_attempts
  from public.invite_redemption_attempts
  where redeemer_id = v_redeemer_id and attempted_at > now() - interval '15 minutes';

  -- Returns before logging: a refused attempt is not counted, so a blocked caller cannot hold
  -- their own lockout open by retrying.
  if v_recent_attempts >= 10 then
    return query select null::uuid, null::uuid,
      'Too many attempts — please wait a while before trying again.'::text, false;
    return;
  end if;

  insert into public.invite_redemption_attempts (redeemer_id) values (v_redeemer_id);

  select * into v_invite
  from public.invite_codes
  where code = upper(trim(p_code))
  for update;

  if not found then
    return query select null::uuid, null::uuid, 'Invite code not found'::text, false;
    return;
  end if;

  if v_invite.status <> 'pending' then
    return query select null::uuid, null::uuid, 'Invite code is no longer valid'::text, false;
    return;
  end if;

  if v_invite.expires_at < now() then
    update public.invite_codes set status = 'expired' where code = v_invite.code;
    return query select null::uuid, null::uuid, 'Invite code has expired'::text, false;
    return;
  end if;

  if v_invite.inviter_id = v_redeemer_id then
    return query select null::uuid, null::uuid, 'You cannot redeem your own invite code'::text, false;
    return;
  end if;

  -- Deliberately the same answer a wrong code gets. Telling a blocked caller they have been
  -- blocked tells them the person is reachable and paying attention, which is the opposite of
  -- what a block is for. See 20261023000000's header.
  if public.is_blocked_between(v_invite.inviter_id, v_redeemer_id) then
    return query select null::uuid, null::uuid, 'Invite code not found'::text, false;
    return;
  end if;

  if exists (
    select 1 from public.couples
    where (partner_a_id = v_redeemer_id or partner_b_id = v_redeemer_id) and status = 'active'
  ) then
    return query select null::uuid, null::uuid, 'You are already connected with a partner'::text, false;
    return;
  end if;

  -- The inviter's side, which auto-accepting would otherwise walk straight into. Checked here
  -- rather than after pairing, so the request stays pending and they get the normal accept screen.
  if exists (
    select 1 from public.couples
    where (partner_a_id = v_invite.inviter_id or partner_b_id = v_invite.inviter_id)
      and status = 'active'
  ) then
    return query select null::uuid, null::uuid,
      'That invite is no longer available — they''re already connected with someone.'::text, false;
    return;
  end if;

  update public.invite_codes
  set status = 'redeemed', redeemed_at = now()
  where code = v_invite.code;

  insert into public.connection_requests (invite_code, inviter_id, requester_id, origin)
  values (v_invite.code, v_invite.inviter_id, v_redeemer_id, p_origin)
  returning * into v_request;

  -- A tapped link pairs them now — unless the two of them have an archive worth being asked
  -- about, in which case the inviter keeps that choice and this stays a request.
  if p_origin = 'link'
    and not private.has_restorable_archive(v_invite.inviter_id, v_redeemer_id)
  then
    perform private.accept_connection_request(v_request.id, false);
    v_auto := true;
  end if;

  return query select v_request.id, v_request.inviter_id, null::text, v_auto;
end;
$$;

