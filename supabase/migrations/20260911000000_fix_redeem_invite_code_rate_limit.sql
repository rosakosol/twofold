-- The invite-code rate limiter has never actually limited anything.
--
-- `redeem_invite_code` counted recent rows in `invite_redemption_attempts`, then logged the current
-- attempt, then validated the code — raising an exception on every failure path ("Invite code not
-- found", "no longer valid", "has expired", "cannot redeem your own", "already connected"). But an
-- exception aborts the whole RPC transaction, and the attempt-log INSERT is *part of that
-- transaction*, so it rolled back too. Net effect: attempts were only ever recorded when redemption
-- succeeded — precisely the case that needs no limiting. Verified empirically against production:
-- seven consecutive failed redemptions left zero rows behind, so the `>= 10` check never fired and
-- invite codes were effectively brute-forceable at unlimited rate.
--
-- The fix is to stop raising on *expected* failures and return them as data instead. The function
-- now returns a row of `(id, inviter_id, error_message)`: on success the first two are populated and
-- `error_message` is null; on a rejected attempt the first two are null and `error_message` carries
-- the same wording the exception used to. Because nothing raises, the transaction commits and the
-- attempt log survives. `BackendService.redeemInviteCode` re-throws `error_message` as
-- `BackendError.requestFailed`, so what the user sees on screen is unchanged.
--
-- 'Not authenticated' still raises: there's no `auth.uid()` to attribute an attempt to, nothing to
-- rate-limit, and it's a programming error rather than a user-facing outcome.
--
-- Side benefit: the "expired" branch marks the code `status = 'expired'` before returning. That
-- write was previously rolled back by the very exception that followed it, so expired codes were
-- never actually being reaped.
--
-- Return type changes, so the old signature has to be dropped rather than replaced.

drop function if exists public.redeem_invite_code(text);

create function public.redeem_invite_code(p_code text)
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
  -- The cap on genuine guesses is unchanged at 10 per 15 minutes.
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

  insert into public.connection_requests (invite_code, inviter_id, requester_id)
  values (v_invite.code, v_invite.inviter_id, v_redeemer_id)
  returning * into v_request;

  return query select v_request.id, v_request.inviter_id, null::text;
end;
$$;

revoke all on function public.redeem_invite_code(text) from public;
grant execute on function public.redeem_invite_code(text) to authenticated;
