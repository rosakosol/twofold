-- Three related hardening changes to partner pairing:
--
-- 1. Invite codes no longer encode the inviter's name (was "ROSA-4821" — guessable if you know
--    who you're targeting, and the root cause of a real bug where a code generated while
--    `AppModel.currentUser.name` was still the pre-load placeholder "You" would say "You invited
--    you to Twofold" forever). Codes are now 8 fully random letters (XXXX-XXXX, ~26^8 ≈ 209
--    billion combinations, matching the placeholder text already shown in the redeem UI). The
--    inviter's name for display is now a real lookup (get_invite_code_inviter_name) instead of a
--    guess parsed from the code text.
--
-- 2. Rate limiting: redeem_invite_code was a plain RPC any authenticated user could call
--    directly with no attempt throttling — combined with the old code's low suffix entropy
--    (~9,000 combinations) this made brute-forcing a specific target's code a real risk. Caps
--    each caller to 5 attempts per 15 minutes regardless of which code(s) they're trying.
--
-- 3. Double verification: redeeming a code no longer immediately creates an active couple — it
--    creates a pending connection_request that only the *inviter* can accept or decline. A
--    successful brute-force guess (or a wrong code typed by someone else entirely) now only
--    produces a request the real inviter can see and reject, rather than silently pairing an
--    attacker as the partner.

-- ---------------------------------------------------------------------------
-- 1. Random invite codes + real inviter-name lookup
-- ---------------------------------------------------------------------------

create or replace function public.create_invite_code()
returns public.invite_codes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_inviter_id uuid := auth.uid();
  v_row public.invite_codes;
begin
  if v_inviter_id is null then
    raise exception 'Not authenticated';
  end if;

  loop
    v_code := (
      select string_agg(chr(65 + floor(random() * 26)::int), '') from generate_series(1, 4)
    ) || '-' || (
      select string_agg(chr(65 + floor(random() * 26)::int), '') from generate_series(1, 4)
    );
    exit when not exists (select 1 from public.invite_codes where code = v_code);
  end loop;

  insert into public.invite_codes (code, inviter_id)
  values (v_code, v_inviter_id)
  returning * into v_row;

  return v_row;
end;
$$;

drop function if exists public.create_invite_code(text);
revoke all on function public.create_invite_code() from public;
grant execute on function public.create_invite_code() to authenticated;

-- Safe to expose: equivalent to what a real invite link/email would already tell you ("Bob
-- invited you"), just looked up for real instead of guessed from the code's own text. Only
-- resolves for a code that's actually still pending and unexpired.
create or replace function public.get_invite_code_inviter_name(p_code text)
returns text
language sql
security definer
set search_path = public
stable
as $$
  select p.first_name
  from public.invite_codes i
  join public.profiles p on p.id = i.inviter_id
  where i.code = upper(trim(p_code)) and i.status = 'pending' and i.expires_at > now();
$$;

revoke all on function public.get_invite_code_inviter_name(text) from public;
grant execute on function public.get_invite_code_inviter_name(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Rate limiting
-- ---------------------------------------------------------------------------

create table public.invite_redemption_attempts (
  id uuid primary key default gen_random_uuid(),
  redeemer_id uuid not null references public.profiles (id) on delete cascade,
  attempted_at timestamptz not null default now()
);

create index invite_redemption_attempts_redeemer_idx
  on public.invite_redemption_attempts (redeemer_id, attempted_at);

alter table public.invite_redemption_attempts enable row level security;
-- No policies for any client role — only the security-definer redeem_invite_code RPC below
-- ever touches this table.

-- ---------------------------------------------------------------------------
-- 3. Double verification (connection_requests)
-- ---------------------------------------------------------------------------

create table public.connection_requests (
  id uuid primary key default gen_random_uuid(),
  invite_code text not null references public.invite_codes (code),
  inviter_id uuid not null references public.profiles (id) on delete cascade,
  requester_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint connection_requests_distinct check (inviter_id <> requester_id)
);

create index connection_requests_inviter_idx on public.connection_requests (inviter_id, status);
create index connection_requests_requester_idx on public.connection_requests (requester_id, status);

alter table public.connection_requests enable row level security;

-- Each side can see requests they're party to — the inviter to review/act on them, the
-- requester to check whether theirs has been accepted yet.
create policy "connection_requests_select_inviter_or_requester" on public.connection_requests
  for select using (inviter_id = auth.uid() or requester_id = auth.uid());
-- No insert/update policy for any client role — only the security-definer RPCs below create or
-- resolve a request.

-- Return type is changing (was public.couples) — CREATE OR REPLACE can't do that, has to drop first.
drop function if exists public.redeem_invite_code(text);

create function public.redeem_invite_code(p_code text)
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

  if v_recent_attempts >= 5 then
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

  -- Consumed immediately — a second guesser (or the code's real owner trying again) can't also
  -- redeem it while this first request is still pending the inviter's decision.
  update public.invite_codes
  set status = 'redeemed', redeemed_at = now()
  where code = v_invite.code;

  insert into public.connection_requests (invite_code, inviter_id, requester_id)
  values (v_invite.code, v_invite.inviter_id, v_redeemer_id)
  returning * into v_request;

  return v_request;
end;
$$;

revoke all on function public.redeem_invite_code(text) from public;
grant execute on function public.redeem_invite_code(text) to authenticated;

-- respond_to_connection_request: only the inviter may call this. Declining just closes out the
-- request — the code stays consumed either way (see redeem_invite_code above), so a declined
-- requester (or an attacker who guessed right) can't retry the same code; the real partner would
-- need a freshly generated one. Accepting creates the actual couple — same insert +
-- started_dating_on reconciliation `redeem_invite_code` used to do inline before this migration.
create or replace function public.respond_to_connection_request(p_request_id uuid, p_accept boolean)
returns public.couples
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.connection_requests;
  v_caller_id uuid := auth.uid();
  v_couple public.couples;
  v_started_dating_on date;
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

  select coalesce(inviter.anniversary_date, requester.anniversary_date)
  into v_started_dating_on
  from public.profiles inviter, public.profiles requester
  where inviter.id = v_request.inviter_id and requester.id = v_request.requester_id;

  insert into public.couples (partner_a_id, partner_b_id, status, started_dating_on)
  values (v_request.inviter_id, v_request.requester_id, 'active', v_started_dating_on)
  returning * into v_couple;
  -- enforce_single_active_couple (existing trigger) raises if either partner already has one,
  -- aborting this whole transaction.

  update public.invite_codes set couple_id = v_couple.id where code = v_request.invite_code;

  update public.connection_requests
  set status = 'accepted', responded_at = now()
  where id = p_request_id;

  return v_couple;
end;
$$;

revoke all on function public.respond_to_connection_request(uuid, boolean) from public;
grant execute on function public.respond_to_connection_request(uuid, boolean) to authenticated;

-- Incoming requests awaiting *my* decision, with the requester's display info for the review UI.
create or replace function public.fetch_pending_connection_requests()
returns table (
  id uuid,
  requester_id uuid,
  requester_first_name text,
  requester_avatar_path text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select cr.id, cr.requester_id, p.first_name, p.avatar_path, cr.created_at
  from public.connection_requests cr
  join public.profiles p on p.id = cr.requester_id
  where cr.inviter_id = auth.uid() and cr.status = 'pending'
  order by cr.created_at desc;
$$;

revoke all on function public.fetch_pending_connection_requests() from public;
grant execute on function public.fetch_pending_connection_requests() to authenticated;
