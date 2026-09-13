-- ---------------------------------------------------------------------------
-- Blocking someone
-- ---------------------------------------------------------------------------
--
-- The companion to the reporting path added alongside this. Apple's Guideline 1.2 asks for four
-- things from an app where one person can put content in front of another — filtering, reporting,
-- blocking, published contact details — and this is the third.
--
-- What already existed was most of the protection and none of the control. Declining a connection
-- request consumes the invite code either way (see 20260829000600's header), so a declined
-- stranger cannot retry the same code and would need a freshly generated one; removing a partner
-- dissolves the couple. So repeat unsolicited contact was already hard. What there was no way to
-- say was "not this person, ever" — and a protection nobody can see or invoke is not one they can
-- rely on when they are frightened.
--
-- ---------------------------------------------------------------------------
-- A block refuses quietly
-- ---------------------------------------------------------------------------
--
-- `redeem_invite_code` returns 'Invite code not found' to a blocked caller — the same answer a
-- wrong code gets, rather than anything that confirms a block exists. Someone who learns they have
-- been blocked has learned that the person they were looking for is reachable, is paying
-- attention, and can be reached another way. The point of a block is to end the conversation, not
-- to send one last message through it.
--
-- Symmetric on purpose: it refuses whether the blocker is the inviter or the redeemer. Blocking
-- someone should not still let them pull you into a couple by handing you a code.
--
-- ---------------------------------------------------------------------------
-- Blocking a current partner disconnects first
-- ---------------------------------------------------------------------------
--
-- `block_profile` calls `leave_couple` when the two are actively paired, because a block that left
-- the couple intact would be a promise the rest of the app does not keep: they would still see
-- every trip, memory and photo.
--
-- It does NOT touch the archive. Deleting shared data is the 90-day timer's job and nothing
-- else's (20261005000000), and a block must not become a way to bring that date forward for the
-- other person — which is exactly the unilateral destruction that migration removed. The archive
-- stays visible to both, and expires when it was always going to.

create table if not exists public.blocked_profiles (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocked_profiles_distinct check (blocker_id <> blocked_id)
);

comment on table public.blocked_profiles is
  'One row per "I do not want to hear from this person again". Readable and writable only by the '
  'blocker: being blocked is not something the blocked person is told, here or anywhere.';

create index if not exists blocked_profiles_blocked_idx on public.blocked_profiles (blocked_id);

alter table public.blocked_profiles enable row level security;

-- Only ever your own rows, in every direction. A policy letting someone read rows where they are
-- the *blocked* party would tell them they had been blocked, which is the one thing this must not
-- do. The RPCs below run security definer precisely so enforcement can see both sides.
create policy "blocked_profiles_select_own" on public.blocked_profiles
  for select to authenticated using (blocker_id = auth.uid());

create policy "blocked_profiles_insert_own" on public.blocked_profiles
  for insert to authenticated with check (blocker_id = auth.uid());

create policy "blocked_profiles_delete_own" on public.blocked_profiles
  for delete to authenticated using (blocker_id = auth.uid());

-- ---------------------------------------------------------------------------

create or replace function public.is_blocked_between(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.blocked_profiles
    where (blocker_id = p_a and blocked_id = p_b)
       or (blocker_id = p_b and blocked_id = p_a)
  );
$$;

comment on function public.is_blocked_between(uuid, uuid) is
  'True if either of these two has blocked the other. Direction-agnostic: a block stops contact '
  'both ways, so the person who did the blocking cannot accidentally re-open it either.';

revoke all on function public.is_blocked_between(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------

create or replace function public.block_profile(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_couple_id uuid;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  if p_profile_id = v_uid then
    raise exception 'You cannot block yourself';
  end if;

  -- Disconnect first, if they are the current partner. See this migration's header: leaving the
  -- couple intact would leave them reading everything, and the archive is deliberately untouched.
  select id into v_couple_id
  from public.couples
  where status = 'active'
    and ((partner_a_id = v_uid and partner_b_id = p_profile_id)
      or (partner_b_id = v_uid and partner_a_id = p_profile_id));

  if v_couple_id is not null then
    perform public.leave_couple(v_couple_id);
  end if;

  insert into public.blocked_profiles (blocker_id, blocked_id)
  values (v_uid, p_profile_id)
  on conflict do nothing;
end;
$$;

revoke all on function public.block_profile(uuid) from public, anon;
grant execute on function public.block_profile(uuid) to authenticated;

create or replace function public.unblock_profile(p_profile_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.blocked_profiles
  where blocker_id = auth.uid() and blocked_id = p_profile_id;
$$;

revoke all on function public.unblock_profile(uuid) from public, anon;
grant execute on function public.unblock_profile(uuid) to authenticated;
