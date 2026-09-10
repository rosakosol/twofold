-- ---------------------------------------------------------------------------
-- Two people who each played today's question cannot pair
-- ---------------------------------------------------------------------------
--
-- Accepting a connection request fails with
--
--   duplicate key value violates unique constraint "game_sessions_daily_couple_uniq"
--
-- and the pairing does not happen at all — the violation aborts the whole transaction, so the
-- couple is never created and the request stays pending. Reported live.
--
-- The cause is one statement inside the accept, unchanged since solo sessions were introduced:
--
--   update game_sessions set couple_id = <new couple>
--   where couple_id is null and initiator_id in (inviter, requester);
--
-- It adopts every solo session both people have played, which is right — that history is theirs and
-- should follow them into the relationship. But `game_sessions_daily_couple_uniq` is unique on
-- (couple_id, daily_local_date) for non-abandoned daily sessions, and there is nothing stopping two
-- solo dailies for the same date from being adopted at once. Two people who each answered today's
-- question before pairing is not an edge case; for a couple installing the app together it is the
-- likely path.
--
-- It also breaks a second way, which the fix has to cover: re-pairing and restoring an archive
-- revives a couple that may already own a daily session for a date one of them has since played
-- solo.
--
-- ---------------------------------------------------------------------------
-- What happens to the one that cannot be adopted
-- ---------------------------------------------------------------------------
--
-- It stays solo. `couple_id` remains null, so it is still that person's session, still in their
-- history, still theirs to look back on — it simply does not become the couple's record for that
-- day. The alternative, marking it abandoned so it slips past the index, would destroy an answer
-- somebody actually gave to make a constraint happy.
--
-- Which one wins is decided by created_at then id: deterministic, and the earliest answer of the
-- day is a defensible reading of "the couple's daily". Nothing about the loser is lost.

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

  -- Everything that cannot collide moves as it always did: anything not a daily, and any daily the
  -- index already ignores because it was abandoned.
  update public.game_sessions
  set couple_id = v_couple.id
  where couple_id is null
    and initiator_id in (v_request.inviter_id, v_request.requester_id)
    and (not is_daily or status = 'abandoned');

  -- And at most one daily per date, only where the couple has none of its own for that date.
  --
  -- The `not exists` covers the restore case, where the revived couple may already hold a daily for
  -- a day one of them has since played alone. The `id = (select ... limit 1)` covers the common
  -- one, where both of them played the same day.
  update public.game_sessions gs
  set couple_id = v_couple.id
  where gs.couple_id is null
    and gs.is_daily
    and gs.status <> 'abandoned'
    and gs.initiator_id in (v_request.inviter_id, v_request.requester_id)
    and not exists (
      select 1 from public.game_sessions owned
      where owned.couple_id = v_couple.id
        and owned.is_daily
        and owned.status <> 'abandoned'
        and owned.daily_local_date is not distinct from gs.daily_local_date
    )
    and gs.id = (
      select candidate.id
      from public.game_sessions candidate
      where candidate.couple_id is null
        and candidate.is_daily
        and candidate.status <> 'abandoned'
        and candidate.initiator_id in (v_request.inviter_id, v_request.requester_id)
        and candidate.daily_local_date is not distinct from gs.daily_local_date
      order by candidate.created_at, candidate.id
      limit 1
    );

  update public.invite_codes set couple_id = v_couple.id where code = v_request.invite_code;

  update public.connection_requests
  set status = 'accepted', responded_at = now()
  where id = p_request_id;

  return v_couple;
end;
$$;

revoke all on function private.accept_connection_request(uuid, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- And one overload too many
-- ---------------------------------------------------------------------------
--
-- 20261004000000 left two functions standing: `respond_to_connection_request(uuid, boolean,
-- boolean default false)` and a two-argument wrapper. A call supplying two arguments matches both,
-- and Postgres refuses to choose:
--
--   function public.respond_to_connection_request(uuid, boolean) is not unique
--
-- PostgREST happens to sidestep it by resolving on the exact set of *named* arguments, which is why
-- the app has been fine and why this surfaced first from a test calling it directly. That is luck
-- rather than design, and it hid the ambiguity from the place most likely to notice.
--
-- Dropping the wrapper leaves one function whose third argument defaults, which serves both call
-- shapes — the same conclusion 20261006000000 reached for `redeem_invite_code`, reached the other
-- way round here by accident. Installed builds sending two named arguments still resolve.
drop function if exists public.respond_to_connection_request(uuid, boolean);
