-- ---------------------------------------------------------------------------
-- Pairing: a block reaches the requests already in flight, and two pairings cannot race
-- ---------------------------------------------------------------------------
--
-- Four gaps, all at the edges of what 20261023000000 (blocking) and the single-active-couple
-- trigger (20260708102734) were meant to guarantee.
--
-- (1) A block did not reach a request that already existed.
--
--     `redeem_invite_code` refuses a blocked pair, but only at the moment of redeeming. A request
--     raised before the block stayed `pending`, and nothing downstream looked at blocks:
--
--       * the requester blocks the inviter — and the inviter can still tap accept, pairing them
--         with someone who has blocked them and handing over every trip, memory and photo. That is
--         exactly what 20261023000000's header says a block must not allow: "Blocking someone
--         should not still let them pull you into a couple."
--       * the inviter blocks the requester — and the requester can keep calling
--         `send_connection_request_reminder`, and `notify-connection-request` (which only checks
--         for a pending row) pushes "<name> is waiting for you" to the person who blocked them,
--         up to ten times an hour.
--
--     A block now declines every pending request between the two, in either direction, and the
--     rows that are already in that state are declined below. It is a trigger on
--     `blocked_profiles` rather than a line in `block_profile`, because the table's own RLS also
--     lets a client insert a block directly, and that route must not skip it. 'declined' is what
--     account deletion uses for the same purpose (`private.scrub_account`), and from the other
--     side it is indistinguishable from an ordinary decline, so it tells nobody they were blocked.
--
-- (2) Nothing at the point of pairing knew about blocks.
--
--     Every pairing — a new couple or a restored archive, accepted or auto-accepted — makes a
--     couple row `active`, and `enforce_single_active_couple` sees all of them. It now refuses
--     that transition between two people either of whom has blocked the other. This is the
--     backstop for (1), not a replacement: it holds even for a request that slipped past it.
--
-- (3) Two pairings at once could both succeed.
--
--     The trigger's `exists` check takes no lock, so under READ COMMITTED two transactions that
--     each activate a couple sharing a member cannot see each other's uncommitted row, and both
--     commit. The ordinary way to hit it: two partners who each send the other their invite link
--     and both tap at once. Each redeem sees neither of them paired, each auto-accepts, and they
--     end up with two active couples whose data splits between two ids. The same holds for a
--     requester with two pending requests that two inviters accept together.
--
--     The trigger now takes a transaction-scoped advisory lock on each member before checking, in
--     a fixed order so two of them cannot deadlock. The second transaction waits for the first to
--     commit, and its check — a new statement, so a new snapshot — then sees the first couple and
--     refuses. Only on the transition into `active`: an update to a couple that is already active
--     (an anniversary date, a distance) neither needs the lock nor should wait on it.
--
-- (4) A blocked ex could still read the blocker's profile row.
--
--     `profiles_select_self_or_partner` matches a couple of any status, so an ex keeps reading the
--     other's whole row until the archive is purged — `last_active_at`, `timezone`, birthday,
--     `home_place_id` — including after being blocked. 20261114004000 already stopped a blocked
--     person reading the blocker's avatar; this applies the same rule to the row. One direction,
--     the same as that one: it hides the blocker from the blocked, not the reverse. The archive
--     screen already falls back to "Partner" when the row is unreadable
--     (`BackendService.fetchArchivedCouples`).
--
--     The check needs to see a `blocked_profiles` row the viewer's own RLS hides from them, so it
--     goes through a security definer function. The function answers "may I read this row", not
--     "has this person blocked me": for anyone who has never shared a couple with the target it is
--     false either way, so it tells nobody anything the row's absence would not.
--
-- And `get_invite_code_inviter_info` gets the same quiet refusal `redeem_invite_code` gives: a
-- blocked caller holding the blocker's code sees what a wrong code gets, not their name.

-- (2) and (3) --------------------------------------------------------------

create or replace function public.enforce_single_active_couple()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'active' then
    if tg_op = 'INSERT'
       or old.status is distinct from 'active'
       or old.partner_a_id is distinct from new.partner_a_id
       or old.partner_b_id is distinct from new.partner_b_id
    then
      -- See (3) in this migration's header. Lower uuid first, so any two transactions take the
      -- same pair of locks in the same order.
      perform pg_advisory_xact_lock(
        hashtextextended('twofold.couple_member:' || least(new.partner_a_id, new.partner_b_id)::text, 0));
      perform pg_advisory_xact_lock(
        hashtextextended('twofold.couple_member:' || greatest(new.partner_a_id, new.partner_b_id)::text, 0));

      -- See (2). Worded like any other no-longer-available request, not as a block.
      if public.is_blocked_between(new.partner_a_id, new.partner_b_id) then
        raise exception 'This connection is no longer available' using errcode = '42501';
      end if;
    end if;

    if exists (
      select 1 from public.couples
      where status = 'active'
        and id <> new.id
        and (partner_a_id in (new.partner_a_id, new.partner_b_id)
          or partner_b_id in (new.partner_a_id, new.partner_b_id))
    ) then
      raise exception 'One or both partners are already in an active couple';
    end if;
  end if;
  return new;
end;
$$;

-- (1) ----------------------------------------------------------------------

create or replace function private.decline_requests_on_block()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.connection_requests
  set status = 'declined', responded_at = now()
  where status = 'pending'
    and ((inviter_id = new.blocker_id and requester_id = new.blocked_id)
      or (inviter_id = new.blocked_id and requester_id = new.blocker_id));
  return null;
end;
$$;

revoke all on function private.decline_requests_on_block() from public;

drop trigger if exists trg_blocked_profiles_decline_requests on public.blocked_profiles;
create trigger trg_blocked_profiles_decline_requests
  after insert on public.blocked_profiles
  for each row execute function private.decline_requests_on_block();

-- The pairs already blocked with a request still open.
update public.connection_requests r
set status = 'declined', responded_at = now()
where r.status = 'pending'
  and exists (
    select 1 from public.blocked_profiles b
    where (b.blocker_id = r.inviter_id and b.blocked_id = r.requester_id)
       or (b.blocker_id = r.requester_id and b.blocked_id = r.inviter_id)
  );

-- (4) ----------------------------------------------------------------------

create or replace function public.can_read_profile(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_profile_id = auth.uid()
    or (
      exists (
        select 1 from public.couples c
        where (c.partner_a_id = auth.uid() and c.partner_b_id = p_profile_id)
           or (c.partner_b_id = auth.uid() and c.partner_a_id = p_profile_id)
      )
      and not exists (
        select 1 from public.blocked_profiles b
        where b.blocker_id = p_profile_id and b.blocked_id = auth.uid()
      )
    );
$$;

comment on function public.can_read_profile(uuid) is
  'Whether the caller may read this profiles row: their own, or a current or former partner''s '
  'unless that partner has blocked them. See 20261114000100.';

revoke all on function public.can_read_profile(uuid) from public, anon;
grant execute on function public.can_read_profile(uuid) to authenticated;

-- `to authenticated`, where the old one was implicitly `to public`: anon could never match it
-- (auth.uid() is null), and it cannot execute the function above.
drop policy if exists "profiles_select_self_or_partner" on public.profiles;
create policy "profiles_select_self_or_partner" on public.profiles
  for select to authenticated using (public.can_read_profile(id));

-- The inviter lookup -------------------------------------------------------

create or replace function public.get_invite_code_inviter_info(p_code text)
returns table (first_name text, avatar_path text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inviter_id uuid;
  v_first_name text;
  v_avatar_path text;
  v_count int;
begin
  select i.inviter_id, p.first_name, p.avatar_path, i.name_lookup_count
  into v_inviter_id, v_first_name, v_avatar_path, v_count
  from public.invite_codes i
  join public.profiles p on p.id = i.inviter_id
  where i.code = upper(trim(p_code)) and i.status = 'pending' and i.expires_at > now();

  if v_first_name is null then
    return;
  end if;

  -- What a wrong code gets, and before the counter: see this migration's header. Only possible
  -- for a signed-in caller — an anonymous one has no identity to have been blocked.
  if auth.uid() is not null and public.is_blocked_between(v_inviter_id, auth.uid()) then
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
