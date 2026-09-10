-- ---------------------------------------------------------------------------
-- How the code got there
-- ---------------------------------------------------------------------------
--
-- Every connection request looks the same to the inviter, and two quite different things produce
-- one. Someone typed a code they were read out or shown — which anyone who saw it could also type
-- — or someone tapped a link the inviter deliberately sent them in Messages. The first is a
-- security decision. The second is a person confirming what they already did five minutes ago,
-- and asking them to adjudicate it reads as an interrogation.
--
-- So the request records which it was, and the accept screen says something different for each.
--
-- ---------------------------------------------------------------------------
-- This is presentation. It must never become a control.
-- ---------------------------------------------------------------------------
--
-- `origin` is asserted by the client. Nothing here can check it: the app says "this came from a
-- link" and the server has no way to know whether it did. Anyone who can call the RPC can claim
-- 'link'.
--
-- That is fine for what it is used for — the wording on a screen — and it would be a real hole the
-- moment anything else reads it. It must not gate auto-acceptance, skip the inviter's approval, or
-- decide anything about who may pair with whom. The approval step stays exactly as mandatory for
-- both values, because the threat it actually defends against is a forwarded message, and a
-- forwarded message is a link.
--
-- If auto-pairing on links is ever wanted, this column is not the mechanism. That needs a secret
-- the inviter's device generates per recipient and never puts in the shareable URL — a different
-- design, not a stronger version of this one.

create type public.connection_request_origin as enum ('code', 'link');

alter table public.connection_requests
  add column if not exists origin public.connection_request_origin not null default 'code';

comment on column public.connection_requests.origin is
  'How the invitee got the code: typed it, or tapped a link. Client-asserted and unverifiable — '
  'used only to word the inviter''s accept screen. Never gate anything on it.';

-- 'code' as the default is the cautious side: an older client that cannot send this produces the
-- request that reads as needing more scrutiny, not less.

-- ---------------------------------------------------------------------------
-- Redeeming, with the origin recorded
-- ---------------------------------------------------------------------------
--
-- Preserves 20260911000000 exactly and adds one column to the insert. That migration is the reason
-- this function returns its failures as data instead of raising them: an exception aborts the RPC
-- transaction, the attempt-log INSERT is part of that transaction, so it rolled back too and the
-- rate limiter only ever recorded *successful* redemptions — the one case needing no limit. Codes
-- were brute-forceable at unlimited rate until it was fixed.
--
-- Worth stating because the shape looks like something to tidy: every `return query select null,
-- null, '...'` below is load-bearing, and turning any of them back into `raise exception` silently
-- disables the limiter. Only 'Not authenticated' raises, because there is no auth.uid() to
-- attribute an attempt to.
--
-- Replaced by a single two-argument function rather than a pair. A one-argument version alongside
-- a two-argument one with a default would be ambiguous for a call supplying only p_code — and that
-- call is exactly what every installed build makes. With one function carrying the default, those
-- builds keep working and their requests record as 'code'.

drop function if exists public.redeem_invite_code(text);

create function public.redeem_invite_code(
  p_code text,
  p_origin public.connection_request_origin default 'code'
)
returns table (id uuid, inviter_id uuid, error_message text)
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

  -- Deliberately returns *before* logging: a rejected attempt isn't counted, so the 15-minute
  -- window drains on schedule instead of a blocked user extending their own lockout by retrying.
  if v_recent_attempts >= 10 then
    return query select null::uuid, null::uuid,
      'Too many attempts — please wait a while before trying again.'::text;
    return;
  end if;

  insert into public.invite_redemption_attempts (redeemer_id) values (v_redeemer_id);

  select * into v_invite
  from public.invite_codes
  where code = upper(trim(p_code))
  for update;

  if not found then
    return query select null::uuid, null::uuid, 'Invite code not found'::text;
    return;
  end if;

  if v_invite.status <> 'pending' then
    return query select null::uuid, null::uuid, 'Invite code is no longer valid'::text;
    return;
  end if;

  if v_invite.expires_at < now() then
    update public.invite_codes set status = 'expired' where code = v_invite.code;
    return query select null::uuid, null::uuid, 'Invite code has expired'::text;
    return;
  end if;

  if v_invite.inviter_id = v_redeemer_id then
    return query select null::uuid, null::uuid, 'You cannot redeem your own invite code'::text;
    return;
  end if;

  if exists (
    select 1 from public.couples
    where (partner_a_id = v_redeemer_id or partner_b_id = v_redeemer_id) and status = 'active'
  ) then
    return query select null::uuid, null::uuid, 'You are already connected with a partner'::text;
    return;
  end if;

  update public.invite_codes
  set status = 'redeemed', redeemed_at = now()
  where code = v_invite.code;

  insert into public.connection_requests (invite_code, inviter_id, requester_id, origin)
  values (v_invite.code, v_invite.inviter_id, v_redeemer_id, p_origin)
  returning * into v_request;

  return query select v_request.id, v_request.inviter_id, null::text;
end;
$$;

revoke all on function public.redeem_invite_code(text, public.connection_request_origin) from public;
grant execute on function public.redeem_invite_code(text, public.connection_request_origin) to authenticated;

-- ---------------------------------------------------------------------------
-- The inviter's list carries it
-- ---------------------------------------------------------------------------

drop function if exists public.fetch_pending_connection_requests();

create function public.fetch_pending_connection_requests()
returns table (
  id uuid,
  requester_id uuid,
  requester_first_name text,
  requester_avatar_path text,
  created_at timestamptz,
  origin public.connection_request_origin
)
language sql
security definer
set search_path = public
stable
as $$
  select r.id, r.requester_id, p.first_name, p.avatar_path, r.created_at, r.origin
  from public.connection_requests r
  join public.profiles p on p.id = r.requester_id
  where r.inviter_id = auth.uid() and r.status = 'pending'
  order by r.created_at desc;
$$;

revoke all on function public.fetch_pending_connection_requests() from public;
grant execute on function public.fetch_pending_connection_requests() to authenticated;
