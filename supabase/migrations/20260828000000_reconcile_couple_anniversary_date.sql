-- Finishes the reconciliation the 20260710050000_profile_anniversary_date.sql migration deferred:
-- `couples.started_dating_on` was meant to become the source of truth once a couple actually
-- forms, but nothing ever wrote it — `redeem_invite_code` never set it, so it's been silently
-- null for every couple ever created, and the client was reading it as if it were populated
-- (masked by a client-side `.now` fallback that made an unset anniversary look like "today").

-- 1. Seed it at pairing time, from whichever partner actually set one during onboarding.
create or replace function public.redeem_invite_code(p_code text)
returns public.couples
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.invite_codes;
  v_couple public.couples;
  v_redeemer_id uuid := auth.uid();
  v_started_dating_on date;
begin
  if v_redeemer_id is null then
    raise exception 'Not authenticated';
  end if;

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

  -- Either side may have set this during their own onboarding — prefer the inviter's (they
  -- were here first) and fall back to the redeemer's.
  select coalesce(inviter.anniversary_date, redeemer.anniversary_date)
  into v_started_dating_on
  from public.profiles inviter, public.profiles redeemer
  where inviter.id = v_invite.inviter_id and redeemer.id = v_redeemer_id;

  insert into public.couples (partner_a_id, partner_b_id, status, started_dating_on)
  values (v_invite.inviter_id, v_redeemer_id, 'active', v_started_dating_on)
  returning * into v_couple;
  -- enforce_single_active_couple (existing trigger) raises if either partner
  -- is already active elsewhere, aborting this whole transaction.

  update public.invite_codes
  set status = 'redeemed', redeemed_at = now(), couple_id = v_couple.id
  where code = v_invite.code;

  return v_couple;
end;
$$;

-- 2. Let either paired partner update it going forward — direct client writes to `couples`
-- stay blocked by RLS (see 20260708104308_couple_rpc_functions.sql), so this is the only
-- sanctioned way to change it post-pairing, mirroring redeem_invite_code/leave_couple.
create or replace function public.update_couple_anniversary_date(p_couple_id uuid, p_date date)
returns public.couples
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
  v_couple public.couples;
begin
  if v_caller_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_couple from public.couples where id = p_couple_id for update;

  if not found then
    raise exception 'Couple not found';
  end if;

  if v_couple.partner_a_id <> v_caller_id and v_couple.partner_b_id <> v_caller_id then
    raise exception 'Not a member of this couple';
  end if;

  update public.couples
  set started_dating_on = p_date
  where id = p_couple_id
  returning * into v_couple;

  return v_couple;
end;
$$;

revoke all on function public.update_couple_anniversary_date(uuid, date) from public;
grant execute on function public.update_couple_anniversary_date(uuid, date) to authenticated;

-- 3. Backfill every already-active couple that's been silently reading as null/`.now` since
-- pairing, same coalesce-preferring-partner-a logic as the RPC above.
update public.couples c
set started_dating_on = coalesce(pa.anniversary_date, pb.anniversary_date)
from public.profiles pa, public.profiles pb
where pa.id = c.partner_a_id
  and pb.id = c.partner_b_id
  and c.started_dating_on is null
  and coalesce(pa.anniversary_date, pb.anniversary_date) is not null;
