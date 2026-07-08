-- Privileged couple-lifecycle operations, exposed as RPC-callable Postgres
-- functions rather than direct table writes. RLS deliberately blocks clients
-- from inserting/updating `couples` and redeeming `invite_codes` directly —
-- these functions are the only sanctioned way to do it, each running as a
-- single atomic transaction under `security definer`.

-- ---------------------------------------------------------------------------
-- create_invite_code: generates a unique NAME-1234 style code for the caller.
-- ---------------------------------------------------------------------------

create or replace function public.create_invite_code(p_first_name text default '')
returns public.invite_codes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_prefix text := upper(regexp_replace(coalesce(nullif(trim(p_first_name), ''), 'TWOFOLD'), '[^A-Za-z]', '', 'g'));
  v_inviter_id uuid := auth.uid();
  v_row public.invite_codes;
begin
  if v_inviter_id is null then
    raise exception 'Not authenticated';
  end if;

  if v_prefix = '' then
    v_prefix := 'TWOFOLD';
  end if;

  loop
    v_code := v_prefix || '-' || lpad(floor(random() * 9000 + 1000)::text, 4, '0');
    exit when not exists (select 1 from public.invite_codes where code = v_code);
  end loop;

  insert into public.invite_codes (code, inviter_id)
  values (v_code, v_inviter_id)
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.create_invite_code(text) from public;
grant execute on function public.create_invite_code(text) to authenticated;

-- ---------------------------------------------------------------------------
-- redeem_invite_code: atomically validates a code and creates the couple.
-- Locks the invite_codes row for the duration of the transaction so two
-- simultaneous redemption attempts can't both succeed.
-- ---------------------------------------------------------------------------

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

  insert into public.couples (partner_a_id, partner_b_id, status)
  values (v_invite.inviter_id, v_redeemer_id, 'active')
  returning * into v_couple;
  -- enforce_single_active_couple (existing trigger) raises if either partner
  -- is already active elsewhere, aborting this whole transaction.

  update public.invite_codes
  set status = 'redeemed', redeemed_at = now(), couple_id = v_couple.id
  where code = v_invite.code;

  return v_couple;
end;
$$;

revoke all on function public.redeem_invite_code(text) from public;
grant execute on function public.redeem_invite_code(text) to authenticated;

-- ---------------------------------------------------------------------------
-- leave_couple: dissolves a couple. Either member may call it unilaterally.
-- Trips/memories remain readable (per the RLS design) but become read-only
-- the moment status flips to 'dissolved'.
-- ---------------------------------------------------------------------------

create or replace function public.leave_couple(p_couple_id uuid)
returns public.couples
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple public.couples;
  v_caller_id uuid := auth.uid();
begin
  if v_caller_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_couple from public.couples where id = p_couple_id for update;

  if not found then
    raise exception 'Couple not found';
  end if;

  if v_couple.partner_a_id <> v_caller_id and v_couple.partner_b_id <> v_caller_id then
    raise exception 'You are not a member of this couple';
  end if;

  if v_couple.status = 'dissolved' then
    raise exception 'This couple has already been dissolved';
  end if;

  update public.couples
  set status = 'dissolved', dissolved_at = now(), dissolved_by = v_caller_id
  where id = p_couple_id
  returning * into v_couple;

  return v_couple;
end;
$$;

revoke all on function public.leave_couple(uuid) from public;
grant execute on function public.leave_couple(uuid) to authenticated;
