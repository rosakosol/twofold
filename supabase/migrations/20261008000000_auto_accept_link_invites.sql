-- ---------------------------------------------------------------------------
-- A tapped link connects the two of them directly
-- ---------------------------------------------------------------------------
--
-- Redeeming from a link now pairs immediately instead of raising a request the inviter has to
-- accept. Typing a code still raises one.
--
-- The reasoning is the ordinary case: an inviter who sent a link in Messages chose the recipient
-- themselves, so being asked to confirm that person a minute later is a question they have already
-- answered. A typed code is different — it was read aloud, or shown on a screen, and anyone who
-- saw it can type it, so somebody should approve.
--
-- ---------------------------------------------------------------------------
-- What this gives up, stated plainly
-- ---------------------------------------------------------------------------
--
-- 20261006000000 says `origin` must never gate anything, because it is asserted by the client and
-- the server cannot check it. This gates on it. That comment is now wrong and this one replaces
-- it, so the trade is written down rather than discovered:
--
--   * Anyone able to call this RPC can claim 'link' and pair without approval. Possession of a
--     live code becomes sufficient, where before it only produced a request that could be
--     declined. A forwarded message is a link, and this cannot tell the two apart.
--   * The protection that remains is the code itself: 8 letters (26^8, ~37.6 bits), single use,
--     3-day expiry, 10 redemption attempts per 15 minutes, and permanently retired afterwards —
--     `code` is the primary key and no row is ever deleted, so one is never reissued.
--
-- Two things are deliberately kept as the backstop, because pairing is now unsupervised:
--
--   1. The inviter is told. `connection_accepted` already notifies, and this path fires it too —
--      an unsupervised pairing that nobody is informed of would be indefensible.
--   2. It is reversible. `leave_couple` is unchanged.
--
-- ---------------------------------------------------------------------------
-- Except where there is something to decide
-- ---------------------------------------------------------------------------
--
-- Auto-accept is skipped when the two of them have a restorable archive. Re-pairing inside 90 days
-- offers the inviter their old memories back (20261004000000), and that choice can only be made at
-- the moment of accepting — it reuses the couple row, so once a new one exists there is nothing to
-- reuse. Silently pairing them would take that decision away permanently and quietly, which is a
-- worse outcome than one extra tap for the rarer case.

-- ---------------------------------------------------------------------------
-- The acceptance, extracted
-- ---------------------------------------------------------------------------
--
-- Lifted verbatim out of `respond_to_connection_request` so both callers run the same code. It
-- deliberately performs no authorisation of its own: the two callers decide who may do this, and a
-- `private` function that pairs anyone is only safe because nothing outside those two can reach it.
create or replace function private.accept_connection_request(
  p_request_id uuid,
  p_restore_archive boolean
)
returns public.couples
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.connection_requests;
  v_couple public.couples;
  v_started_dating_on date;
  v_archive_id uuid;
begin
  select * into v_request from public.connection_requests where id = p_request_id;
  if not found then
    raise exception 'Connection request not found';
  end if;

  if p_restore_archive then
    select id into v_archive_id
    from public.couples
    where status = 'dissolved'
      and ((partner_a_id = v_request.inviter_id and partner_b_id = v_request.requester_id)
        or (partner_b_id = v_request.inviter_id and partner_a_id = v_request.requester_id))
      and scheduled_purge_at > now()
    order by dissolved_at desc nulls last
    limit 1
    for update;
  end if;

  if v_archive_id is not null then
    update public.couples
    set status = 'active', dissolved_at = null, dissolved_by = null
    where id = v_archive_id
    returning * into v_couple;

    delete from public.couple_archive_preferences where couple_id = v_archive_id;
  else
    select coalesce(inviter.anniversary_date, requester.anniversary_date)
    into v_started_dating_on
    from public.profiles inviter, public.profiles requester
    where inviter.id = v_request.inviter_id and requester.id = v_request.requester_id;

    insert into public.couples (partner_a_id, partner_b_id, status, started_dating_on)
    values (v_request.inviter_id, v_request.requester_id, 'active', v_started_dating_on)
    returning * into v_couple;
  end if;

  update public.game_sessions
  set couple_id = v_couple.id
  where couple_id is null
    and initiator_id in (v_request.inviter_id, v_request.requester_id);

  update public.invite_codes set couple_id = v_couple.id where code = v_request.invite_code;

  update public.connection_requests
  set status = 'accepted', responded_at = now()
  where id = p_request_id;

  return v_couple;
end;
$$;

revoke all on function private.accept_connection_request(uuid, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Whether these two have something worth being asked about
-- ---------------------------------------------------------------------------

create or replace function private.has_restorable_archive(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.couples
    where status = 'dissolved'
      and ((partner_a_id = p_a and partner_b_id = p_b) or (partner_b_id = p_a and partner_a_id = p_b))
      and scheduled_purge_at > now()
  );
$$;

revoke all on function private.has_restorable_archive(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The inviter's own accept, now delegating
-- ---------------------------------------------------------------------------

create or replace function public.respond_to_connection_request(
  p_request_id uuid,
  p_accept boolean,
  p_restore_archive boolean default false
)
returns public.couples
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.connection_requests;
  v_caller_id uuid := auth.uid();
begin
  if v_caller_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_request from public.connection_requests where id = p_request_id for update;

  if not found then
    raise exception 'Connection request not found';
  end if;

  if v_request.inviter_id <> v_caller_id then
    raise exception 'Only the inviter can respond to this request';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'This request has already been responded to';
  end if;

  if not p_accept then
    update public.connection_requests
    set status = 'declined', responded_at = now()
    where id = p_request_id;
    return null;
  end if;

  return private.accept_connection_request(p_request_id, p_restore_archive);
end;
$$;

revoke all on function public.respond_to_connection_request(uuid, boolean, boolean) from public;
grant execute on function public.respond_to_connection_request(uuid, boolean, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Redeeming, which now sometimes finishes the job
-- ---------------------------------------------------------------------------
--
-- Everything about the rate limiter is unchanged and remains load-bearing: rejections return as
-- data rather than raising, because an exception rolls back the attempt log inside the same
-- transaction and the limit stops counting. See 20260911000000.

drop function if exists public.redeem_invite_code(text, public.connection_request_origin);
drop function if exists public.redeem_invite_code(text);

create function public.redeem_invite_code(
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

revoke all on function public.redeem_invite_code(text, public.connection_request_origin) from public;
grant execute on function public.redeem_invite_code(text, public.connection_request_origin) to authenticated;
