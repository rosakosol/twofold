-- ---------------------------------------------------------------------------
-- What happens to a shared history when a couple comes apart, and if they come back
-- ---------------------------------------------------------------------------
--
-- Unpairing does not delete anything and never did — `leave_couple` flips the couple to
-- 'dissolved' and everything stays readable in Settings -> Archived Data. That stays true, and it
-- is the point: a breakup must not be a button one person can press to destroy the other person's
-- copy of a shared decade.
--
-- What was missing was an end. Archives sat forever, and the only ways to remove one were the two
-- unilateral deletes that 20261003000000 closed. So:
--
--   * Unpairing or deleting an account archives the shared data and starts a 90-day clock.
--   * At 90 days it is permanently deleted, automatically, without needing either person to agree.
--   * If the two of them re-pair inside that window, they are offered it back.
--   * Re-pair after the window and there is nothing to offer — it is already gone, so they start
--     fresh with no special handling. That falls out; it is not a separate rule.
--
-- Deleting without consent is deliberate here and is not the thing 20261003000000 prevents. That
-- migration stops one partner *choosing* to destroy the other's copy. This is a fixed retention
-- period that applies to both of them equally, that neither can trigger early alone, and that
-- neither can aim at the other.
--
-- ---------------------------------------------------------------------------
-- Restoring reuses the couple row. It cannot do anything else.
-- ---------------------------------------------------------------------------
--
-- Every memory photo lives at `memory-photos/{couple_id}/...` and is readable through
-- `memory_photos_select_members`, which asks `is_couple_member((storage.foldername(name))[1])` —
-- membership, with no status check, which is exactly why a dissolved couple's photos stay
-- readable. Moving content to a new couple row would leave every one of those files under the old
-- id: the rows would point at paths their new couple has no claim to, and the photos would go
-- dark. Physically copying the objects is not something SQL can do.
--
-- So restoring revives the original row — same `couple_id`, so every foreign key, every storage
-- path and every policy keeps working untouched. The cost is that it can only happen at the moment
-- of re-pairing, before a new couple row exists to have to reconcile with.

alter table public.couples
  add column if not exists scheduled_purge_at timestamptz;

comment on column public.couples.scheduled_purge_at is
  'When this dissolved couple''s shared data is permanently deleted. Set automatically 90 days out '
  'when a couple dissolves, cleared if they re-pair and restore. Null while active.';

-- Deliberately not a config table. A retention period people are told about at the point of
-- unpairing should not be silently adjustable per couple.
create or replace function public.archive_retention_interval()
returns interval
language sql
immutable
as $$ select interval '90 days'; $$;

-- ---------------------------------------------------------------------------
-- The clock is set by the status change itself
-- ---------------------------------------------------------------------------
--
-- A trigger rather than a line in `leave_couple`, because dissolving happens from more than one
-- place — `leave_couple`, `delete_own_account`, and whatever comes next. Anything that sets the
-- status gets the clock, including code not written yet, which is the only way this stays true.
--
-- On INSERT as well as UPDATE. A dissolved couple with no deadline is immortal: the purge job
-- requires a non-null stamp, so it is never deleted, and it stays restorable forever. Only an
-- UPDATE trigger leaves that row reachable by anything that inserts a dissolved couple directly.
create or replace function private.stamp_couple_archive_clock()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'dissolved' and new.scheduled_purge_at is null then
      new.scheduled_purge_at := coalesce(new.dissolved_at, now()) + public.archive_retention_interval();
    end if;
    return new;
  end if;

  if new.status = 'dissolved' and old.status is distinct from 'dissolved' then
    new.scheduled_purge_at := coalesce(new.dissolved_at, now()) + public.archive_retention_interval();
  elsif new.status = 'active' and old.status is distinct from 'active' then
    -- Restored. The data is live again, so it is not an archive and has no expiry.
    new.scheduled_purge_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_couples_archive_clock on public.couples;
create trigger trg_couples_archive_clock
  before insert or update on public.couples
  for each row
  execute function private.stamp_couple_archive_clock();

-- Existing archives get the same deadline, measured from when they actually ended rather than from
-- this deploy — someone who unpaired a year ago should not get a fresh 90 days of retention.
update public.couples
set scheduled_purge_at = coalesce(dissolved_at, now()) + public.archive_retention_interval()
where status = 'dissolved' and scheduled_purge_at is null;

-- ---------------------------------------------------------------------------
-- Re-pairing must not hand a couple a fresh set of flights
-- ---------------------------------------------------------------------------
--
-- The monthly flight limit was counted against `couple_id`, and re-pairing is precisely the act of
-- changing that. Either path resets it: start fresh and there is a new couples row with an empty
-- ledger; restore and the revived row would need its counting window moved forward or it would
-- carry a month it had already spent. Both give the same result — a couple sitting at 5 of 5
-- unpairs, re-pairs, and has five more. Every flight costs a real AeroAPI call on lookup and again
-- on every poll, so that is not a technicality.
--
-- The mistake was treating the couple row as the identity that owns the allowance. It isn't: it is
-- the two people, and they are the same two people on the other side of a re-pair. So the month's
-- usage is counted against them.
--
-- What this trades: someone who tracks flights, unpairs, and pairs with a NEW partner inside the
-- same calendar month brings their spent flights into that relationship, so the new partner may
-- find some of the month already gone. That is the deliberate choice — it resets on the 1st like
-- everyone else's, it costs a genuinely re-partnering couple a few flights in one month, and the
-- alternative is an allowance anyone can reset in two taps.
create or replace function public.flights_used_this_month(p_couple_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
  from public.flight_additions a
  where a.added_at >= date_trunc('month', now() at time zone 'utc')
    and a.added_by in (
      select c.partner_a_id from public.couples c where c.id = p_couple_id
      union
      select c.partner_b_id from public.couples c where c.id = p_couple_id
    );
$$;

-- ---------------------------------------------------------------------------
-- What the re-pair prompt needs to know
-- ---------------------------------------------------------------------------

-- The archive these two people could bring back, if there is one. Null when they have no shared
-- past, or when it has already been deleted.
create or replace function public.restorable_archive_with(p_partner_id uuid)
returns table (
  couple_id uuid,
  dissolved_at timestamptz,
  scheduled_purge_at timestamptz,
  memory_count integer,
  trip_count integer,
  flight_count integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  return query
  select
    c.id,
    c.dissolved_at,
    c.scheduled_purge_at,
    (select count(*)::integer from public.memories m where m.couple_id = c.id),
    (select count(*)::integer from public.trips t where t.couple_id = c.id),
    (select count(*)::integer from public.flights f where f.couple_id = c.id)
  from public.couples c
  where c.status = 'dissolved'
    and ((c.partner_a_id = v_me and c.partner_b_id = p_partner_id)
      or (c.partner_b_id = v_me and c.partner_a_id = p_partner_id))
    -- Not `is null or ...`. With the trigger stamping every dissolved row, a null here means
    -- something is wrong with the row, and the safe reading of "we don't know when this expires"
    -- is to leave it alone rather than to offer it back indefinitely.
    and c.scheduled_purge_at > now()
  order by c.dissolved_at desc nulls last
  limit 1;
end;
$$;

revoke all on function public.restorable_archive_with(uuid) from public;
grant execute on function public.restorable_archive_with(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Accepting, with or without the past
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
  v_couple public.couples;
  v_started_dating_on date;
  v_archive_id uuid;
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

  if p_restore_archive then
    -- Their own archive, still inside its window. Locked, because the purge job could otherwise
    -- be deleting this very row while it is being brought back.
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
    -- Revived, not recreated: the id stays the same, so every memory, photo, trip and flight is
    -- simply live again. `scheduled_purge_at` is cleared by trg_couples_archive_clock.
    update public.couples
    set status = 'active',
        dissolved_at = null,
        dissolved_by = null
    where id = v_archive_id
    returning * into v_couple;

    -- Whatever either of them asked for about the archive is spent — this is a live relationship
    -- now, not something to hide or delete.
    delete from public.couple_archive_preferences where couple_id = v_archive_id;
  else
    select coalesce(inviter.anniversary_date, requester.anniversary_date)
    into v_started_dating_on
    from public.profiles inviter, public.profiles requester
    where inviter.id = v_request.inviter_id and requester.id = v_request.requester_id;

    insert into public.couples (partner_a_id, partner_b_id, status, started_dating_on)
    values (v_request.inviter_id, v_request.requester_id, 'active', v_started_dating_on)
    returning * into v_couple;
    -- enforce_single_active_couple (existing trigger) raises if either partner already has one,
    -- aborting this whole transaction.
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

revoke all on function public.respond_to_connection_request(uuid, boolean, boolean) from public;
grant execute on function public.respond_to_connection_request(uuid, boolean, boolean) to authenticated;

-- The two-argument form is what older builds call. Kept so they keep working, and it does what it
-- always did: accept without restoring.
create or replace function public.respond_to_connection_request(p_request_id uuid, p_accept boolean)
returns public.couples
language sql
security definer
set search_path = public
as $$
  select public.respond_to_connection_request(p_request_id, p_accept, false);
$$;

revoke all on function public.respond_to_connection_request(uuid, boolean) from public;
grant execute on function public.respond_to_connection_request(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- The 90 days running out
-- ---------------------------------------------------------------------------

create or replace function private.purge_expired_couple_archives()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple_id uuid;
  v_count integer := 0;
begin
  for v_couple_id in
    select id from public.couples
    where status = 'dissolved'
      and scheduled_purge_at is not null
      and scheduled_purge_at <= now()
  loop
    perform public.purge_couple_data(v_couple_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function private.purge_expired_couple_archives() from public, anon, authenticated;

comment on function private.purge_expired_couple_archives() is
  'Deletes dissolved couples whose 90 days are up. Runs from pg_cron; never callable by a client — '
  'the whole point is that neither partner can bring the deadline forward.';

select cron.schedule(
  'purge-expired-couple-archives',
  '0 3 * * *',
  'select private.purge_expired_couple_archives();'
);
