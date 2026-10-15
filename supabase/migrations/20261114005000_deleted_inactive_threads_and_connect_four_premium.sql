-- ============================================================
-- Deleted means deleted, web forms prove nothing, and Connect 4 needs Premium to play
-- ============================================================
--
-- Four decisions from the QA sweep of 2026-10-15.
--
-- ---------------------------------------------------------------------------
-- 1. A deleted account is inactive the moment it is deleted
-- ---------------------------------------------------------------------------
--
-- Nothing on the server checked account_deleted_at. The app signs a deleted user out
-- (BackendService.rejectIfAccountDeleted), but an access token outlives deletion by up to an hour,
-- and indefinitely if delete-account's sign-out call failed, which it documents as possible. Until
-- then the token read and wrote like any other.
--
-- So PostgREST's pre-request hook refuses every request from a deleted account before it reaches a
-- table or function: one indexed lookup per request, for anonymous callers nothing. Storage doesn't
-- go through PostgREST, so can_access_storage_object refuses them too. Edge functions already
-- refuse them: auth.getUser fails for a soft-deleted user.
--
-- ---------------------------------------------------------------------------
-- 2. A deleted admin loses the role
-- ---------------------------------------------------------------------------
--
-- scrub_account kept feedback_admins rows. It now deletes them, and any already left behind go.
--
-- ---------------------------------------------------------------------------
-- 3. Support threads join only what is genuinely the same conversation
-- ---------------------------------------------------------------------------
--
-- A message joined the newest thread with the same subject and sender address. Two holes:
--
--   * The website form takes any typed address. Anyone could put a stranger's address and subject
--     on a message and land it in the stranger's thread, which the console then linked to the
--     stranger's account. Website-form messages now always start a thread of their own (their own
--     replies come back by the thread's reply-to token, which is unaffected), and an address that
--     has only ever been typed into the form links to no account.
--   * No subject joined everything with no subject. App messages carry none, so every message
--     somebody sent from the app, about anything, became one "(no subject)" thread. A message with
--     no subject now always starts a new one.
--
-- Mail actually sent from an address, under the same subject, still joins its thread, as before.
--
-- ---------------------------------------------------------------------------
-- 4. Connect 4 needs Premium to keep playing
-- ---------------------------------------------------------------------------
--
-- See play_connect_four_move below. The app shows the lapsed state; the board is kept.

-- ---------------------------------------------------------------------------
-- 1. Deleted accounts
-- ---------------------------------------------------------------------------

-- In public, not private: PostgREST runs the hook as the caller's own role, and anon and
-- authenticated have no USAGE on the private schema. There, every request from everybody failed
-- with "permission denied for schema private". Exposed as an RPC as a result, which is harmless:
-- for a live account it does nothing at all.
create or replace function public.reject_deleted_accounts()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null
     and exists (select 1 from public.profiles where id = auth.uid() and account_deleted_at is not null)
  then
    raise exception 'account_deleted' using errcode = '42501',
      hint = 'This account has been deleted.';
  end if;
end;
$$;

revoke all on function public.reject_deleted_accounts() from public;
grant execute on function public.reject_deleted_accounts() to anon, authenticated;

alter role authenticator set pgrst.db_pre_request = 'public.reject_deleted_accounts';
notify pgrst, 'reload config';

create or replace function public.can_access_storage_object(
  p_kind text,
  p_path text,
  p_op text default 'read'
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_parts text[];
  v_owner uuid;
  v_couple uuid;
  v_person uuid;
  v_parent uuid;
begin
  if v_uid is null or p_kind is null or p_path is null or p_op is null then
    return false;
  end if;

  -- A deleted account reads and writes nothing, from the moment it is deleted. Storage requests
  -- don't pass through PostgREST, so the pre-request check below doesn't reach them; this does.
  if exists (select 1 from public.profiles where id = v_uid and account_deleted_at is not null) then
    return false;
  end if;

  if p_op not in ('read', 'write', 'delete') then
    return false;
  end if;

  v_parts := string_to_array(p_path, '/');

  if v_parts is null or exists (
    select 1 from unnest(v_parts) as segment where segment in ('', '.', '..')
  ) then
    return false;
  end if;

  case p_kind

    -- avatars/{ownerID}/avatar.jpg, avatars/{ownerID}/partner-avatar.jpg
    when 'avatar' then
      if coalesce(array_length(v_parts, 1), 0) <> 2 then return false; end if;
      begin
        v_owner := v_parts[1]::uuid;
      exception when invalid_text_representation then
        return false;
      end;

      if p_op in ('write', 'delete') then
        return v_owner = v_uid;
      end if;

      -- New: see (2) in the header. Checked before every widening clause below, because each of
      -- them is a relationship that a block is meant to end.
      if exists (
        select 1 from blocked_profiles b where b.blocker_id = v_owner and b.blocked_id = v_uid
      ) then
        return false;
      end if;

      return v_owner = v_uid
        or exists (
          select 1 from couples c
          where (c.partner_a_id = v_uid and c.partner_b_id = v_owner)
             or (c.partner_b_id = v_uid and c.partner_a_id = v_owner)
        )
        or exists (
          select 1 from connection_requests r
          where (r.inviter_id = v_uid and r.requester_id = v_owner)
             or (r.requester_id = v_uid and r.inviter_id = v_owner)
        )
        or exists (
          select 1 from invite_codes i
          where i.inviter_id = v_owner and i.status = 'pending' and i.expires_at > now()
        );

    -- drawing-pads/{coupleID}/{personID}/pad.png
    when 'drawing-pad' then
      if coalesce(array_length(v_parts, 1), 0) <> 3 then return false; end if;
      begin
        v_couple := v_parts[1]::uuid;
        v_person := v_parts[2]::uuid;
      exception when invalid_text_representation then
        return false;
      end;

      if p_op = 'delete' then return false; end if;
      -- `is_couple_active` is new: see (3) in the header.
      if p_op = 'write' then
        return v_person = v_uid and is_couple_member(v_couple) and is_couple_active(v_couple);
      end if;
      return is_couple_member(v_couple);

    -- memory-photos/{coupleID}/{memoryID}/{uuid}.jpg
    when 'memory-photo' then
      if coalesce(array_length(v_parts, 1), 0) <> 3 then return false; end if;
      begin
        v_couple := v_parts[1]::uuid;
      exception when invalid_text_representation then
        return false;
      end;
      if p_op = 'read' then return is_couple_member(v_couple); end if;
      return is_couple_member(v_couple) and is_couple_active(v_couple);

    -- flight-documents/{coupleID}/{parentID}/{uuid}.{ext}
    when 'flight-document' then
      if coalesce(array_length(v_parts, 1), 0) <> 3 then return false; end if;
      begin
        v_couple := v_parts[1]::uuid;
      exception when invalid_text_representation then
        return false;
      end;

      -- New: see (1) in the header. A parent that is not a uuid cannot be a flight, so it is left to
      -- the membership rule below exactly as before rather than turned into a refusal here.
      begin
        v_parent := v_parts[2]::uuid;
      exception when invalid_text_representation then
        v_parent := null;
      end;
      if v_parent is not null
         and exists (select 1 from flights f where f.id = v_parent and f.couple_id = v_couple)
         and not can_see_flight(v_parent) then
        return false;
      end if;

      if p_op = 'write' then return is_couple_member(v_couple) and is_couple_active(v_couple); end if;
      return is_couple_member(v_couple);

    else
      return false;
  end case;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Admin roles
-- ---------------------------------------------------------------------------

create or replace function private.scrub_account(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple_id uuid;
begin
  perform private.enqueue_object_deletions(
    array(select private.profile_object_keys(p_profile_id))
  );

  -- Dissolve any couple this profile is still actively part of, so the remaining partner gets the
  -- normal "partner left" experience rather than their partner silently disappearing. The
  -- trg_couples_archive_clock trigger stamps each one with its deletion date.
  --
  -- Deliberately still the plain UPDATE the original used, not private.dissolve_couple: a deletion
  -- is not a disconnection. Arming the "your subscription lapsed because they left" notice would
  -- name a person whose account no longer exists, and abandoning their games and flights is
  -- already handled by everything downstream of the profile being scrubbed.
  for v_couple_id in
    select id from public.couples
    where (partner_a_id = p_profile_id or partner_b_id = p_profile_id) and status = 'active'
  loop
    update public.couples
    set status = 'dissolved', dissolved_at = now(), dissolved_by = p_profile_id
    where id = v_couple_id;
  end loop;

  -- Nothing this account started can be finished by somebody else. See the header: an unexpired
  -- invite link would otherwise pair its holder with an account nobody can sign in to.
  update public.invite_codes
  set status = 'expired'
  where inviter_id = p_profile_id and status = 'pending';

  update public.connection_requests
  set status = 'declined', responded_at = now()
  where status = 'pending'
    and (inviter_id = p_profile_id or requester_id = p_profile_id);

  -- Solo sessions only — see 20261111001100. Cascades to game_responses and game_session_rounds.
  delete from public.game_sessions
  where couple_id is null and initiator_id = p_profile_id;

  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects where bucket_id = 'avatars' and (storage.foldername(name))[1] = p_profile_id::text;
  delete from storage.objects where bucket_id = 'drawing-pads' and (storage.foldername(name))[2] = p_profile_id::text;

  delete from public.device_push_tokens where profile_id = p_profile_id;

  -- A deleted account keeps no admin role. Left in place, an admin who deleted their account
  -- (or was deleted) still passed is_support_admin() with any session that outlived the deletion.
  delete from public.feedback_admins where profile_id = p_profile_id;
  delete from public.live_activity_push_tokens where profile_id = p_profile_id;

  -- Anywhere this person's name was copied onto somebody else's row. The notice it belongs to is
  -- retired at the same time: it exists to explain a lapse caused by a person, and once that
  -- person is gone there is no longer anybody to name.
  update public.profiles
  set partner_subscription_lapse_partner_name = null,
      partner_subscription_lapse_shown = true
  where partner_subscription_lapse_partner_name is not null
    and exists (
      select 1 from public.couples c
      where (c.partner_a_id = p_profile_id and c.partner_b_id = profiles.id)
         or (c.partner_b_id = p_profile_id and c.partner_a_id = profiles.id)
    );

  update public.profiles
  set first_name = 'Deleted User',
      avatar_path = null,
      partner_avatar_path = null,
      partner_name = null,
      home_place_id = null,
      partner_home_place_id = null,
      account_deleted_at = now()
  where id = p_profile_id;
end;
$$;

delete from public.feedback_admins
where profile_id in (select id from public.profiles where account_deleted_at is not null);

-- ---------------------------------------------------------------------------
-- 3. Support threads
-- ---------------------------------------------------------------------------

create or replace function private.resolve_support_thread(
  p_to_address text,
  p_subject text,
  p_email text,
  p_profile_id uuid,
  p_at timestamptz,
  p_join_by_subject boolean
)
returns uuid
language plpgsql
security definer
set search_path = private, public
as $$
declare
  v_token text := private.token_from_address(p_to_address);
  v_key text := private.support_thread_key(p_subject, p_email);
  v_id uuid;
begin
  -- The thread's own reply-to token is the strongest evidence there is: it was only ever sent to
  -- the person in that conversation.
  if v_token is not null then
    select id into v_id from public.support_threads where token = v_token;
  end if;

  -- By subject and sender only when the sender is known to own the address (mail sent from it, or
  -- the signed-in account's own), and only for a real subject: "no subject" is not a conversation.
  if v_id is null and p_join_by_subject and nullif(trim(coalesce(p_subject, '')), '') is not null then
    select id into v_id from public.support_threads
    where thread_key = v_key
    order by last_message_at desc
    limit 1;
  end if;

  if v_id is null then
    insert into public.support_threads (thread_key, subject, email, profile_id, created_at, last_message_at)
    values (v_key, nullif(trim(p_subject), ''), lower(trim(p_email)), p_profile_id, p_at, p_at)
    returning id into v_id;
  else
    update public.support_threads
    set last_message_at = greatest(last_message_at, p_at),
        status = 'open',
        handled_at = case when status = 'closed' then null else handled_at end,
        handled_by = case when status = 'closed' then null else handled_by end,
        profile_id = coalesce(profile_id, p_profile_id)
    where id = v_id;
  end if;

  return v_id;
end;
$$;

-- The five-argument form is what ingest_support_email calls: inbound mail, sent from the address.
create or replace function private.resolve_support_thread(
  p_to_address text,
  p_subject text,
  p_email text,
  p_profile_id uuid,
  p_at timestamptz
)
returns uuid
language sql
security definer
set search_path = private, public
as $$
  select private.resolve_support_thread(p_to_address, p_subject, p_email, p_profile_id, p_at, true);
$$;

revoke all on function private.resolve_support_thread(text, text, text, uuid, timestamptz, boolean)
  from public, anon, authenticated;
revoke all on function private.resolve_support_thread(text, text, text, uuid, timestamptz)
  from public, anon, authenticated;

-- Signed in: the address is the account's own, so a real subject may join its thread. Anonymous
-- (the website form): never by subject.
create or replace function public.submit_support_request(
  p_category text,
  p_message text,
  p_subject text default null,
  p_email text default null,
  p_name text default null,
  p_source text default 'app',
  p_reported_profile_id uuid default null,
  p_report_surface text default null
)
returns uuid
language plpgsql
security definer
set search_path = private, public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_id uuid;
  v_thread uuid;
  v_reported uuid;
begin
  if coalesce(trim(p_message), '') = '' then
    raise exception 'a message is required' using errcode = '22023';
  end if;
  if coalesce(trim(p_category), '') = '' then
    raise exception 'a category is required' using errcode = '22023';
  end if;
  if p_source not in ('app', 'web') then
    raise exception 'unknown source' using errcode = '22023';
  end if;

  -- A signed-in sender's address is their account's, not whatever was posted. This is the field a
  -- reply is sent to, and letting a caller choose it would make this an open relay for support
  -- replies.
  if v_uid is not null then
    select u.email into v_email from auth.users u where u.id = v_uid;
  else
    v_email := nullif(trim(p_email), '');
    -- One bare address: no display name, no list, nothing that can end a header line. Stricter
    -- than the website's own check only in the characters a real address does not contain.
    if v_email is null
       or length(v_email) > 320
       or v_email !~ '^[^[:space:][:cntrl:]<>,;"@]+@[^[:space:][:cntrl:]<>,;"@]+\.[^[:space:][:cntrl:]<>,;"@]+$' then
      raise exception 'a single valid email address is required' using errcode = '22023';
    end if;
  end if;

  -- See 20261113001100: only a signed-in reporter, only on a report, and never themselves.
  if v_uid is not null and trim(p_category) = 'Report Abuse' and p_reported_profile_id is distinct from v_uid then
    v_reported := p_reported_profile_id;
  end if;

  -- No recipient address: a form submission has no token to carry, so this always resolves by the
  -- derived key or starts a conversation.
  v_thread := private.resolve_support_thread(null, p_subject, v_email, v_uid, now(), v_uid is not null);

  insert into public.support_requests (
    thread_id, profile_id, email, name, category, subject, message, source, thread_key,
    reported_profile_id, report_surface
  )
  values (
    v_thread, v_uid, v_email, nullif(trim(p_name), ''), trim(p_category),
    nullif(trim(p_subject), ''), left(trim(p_message), 5000), p_source,
    private.support_thread_key(p_subject, v_email),
    v_reported, case when v_reported is not null then left(nullif(trim(p_report_surface), ''), 100) end
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.admin_support_requests(
  p_status text default 'open',
  p_limit integer default 100
)
returns table (
  id uuid, thread_id uuid, thread_token text, thread_size bigint, thread_position bigint,
  thread_last_at timestamptz, thread_status text, thread_handler_note text, thread_handled_at timestamptz,
  profile_id uuid, matched_profile_id uuid, email text, name text, category text, subject text,
  message text, source text, direction text, created_at timestamptz,
  reported_profile_id uuid, reported_name text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  return query
    with threads as (
      select * from public.support_threads t
      where p_status is null or t.status = p_status
      order by t.last_message_at desc
      limit least(greatest(coalesce(p_limit, 100), 1), 200)
    )
    select
      r.id, t.id, t.token,
      count(*) over (partition by t.id),
      row_number() over (partition by t.id order by r.seq desc),
      t.last_message_at, t.status, t.handler_note, t.handled_at,
      r.profile_id,
      -- Matched by address only when the address has been shown to be theirs: a thread holding
      -- mail actually sent from it, or an app message from the signed-in account. A website-form
      -- address is whatever was typed, so on its own it links to nobody.
      coalesce(t.profile_id, r.profile_id,
               case when exists (
                 select 1 from public.support_requests x
                 where x.thread_id = t.id and x.direction = 'inbound' and x.source <> 'web'
               ) then (select u.id from auth.users u where lower(u.email) = lower(t.email) limit 1) end),
      r.email, r.name, r.category, r.subject, r.message, r.source,
      coalesce(r.direction, 'inbound'), r.created_at,
      r.reported_profile_id,
      reported.first_name
    from threads t
    join public.support_requests r on r.thread_id = t.id
    left join public.profiles reported on reported.id = r.reported_profile_id
    order by t.last_message_at desc, t.id, r.seq desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Connect 4
-- ---------------------------------------------------------------------------

create or replace function public.play_connect_four_move(p_session_id uuid, p_column int)
returns table (move_number int, finished boolean, winner_id uuid, is_draw boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_session public.game_sessions;
  v_played int;
  v_expected uuid;
  v_board int[];
  v_free int := 0;
  v_winner int;
  v_winner_id uuid;
  v_draw boolean := false;
  v_number int;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_column < 0 or p_column > 6 then
    raise exception 'Column must be between 0 and 6';
  end if;

  select * into v_session from public.game_sessions where id = p_session_id;
  if not found or v_session.game_type <> 'connect_four' then
    raise exception 'No such game';
  end if;

  if v_session.couple_id is null or not public.is_couple_member(v_session.couple_id) then
    raise exception 'Not your game' using errcode = '42501';
  end if;

  -- Connect 4 is Premium to play, not only to start. A couple whose Premium lapsed mid-game used
  -- to keep playing the board they had; now the board waits, intact, until Premium is back.
  -- The same word start_connect_four_session raises, so the app reads both the same way.
  if private.couple_effective_tier(v_session.couple_id) <> 'premium' then
    raise exception 'connect_four_requires_premium' using errcode = 'P0001';
  end if;

  if v_session.status not in ('active', 'waiting_for_partner') then
    raise exception 'connect_four_finished' using errcode = 'P0001';
  end if;

  select count(*) into v_played from public.game_moves where session_id = p_session_id;

  if v_played % 2 = 0 then
    v_expected := v_session.initiator_id;
  else
    select case when c.partner_a_id = v_session.initiator_id then c.partner_b_id else c.partner_a_id end
    into v_expected
    from public.couples c where c.id = v_session.couple_id;
  end if;

  if v_expected is distinct from v_me then
    raise exception 'connect_four_not_your_turn' using errcode = 'P0001';
  end if;

  v_board := private.connect_four_board(p_session_id);
  if v_board[0 * 7 + p_column + 1] <> 0 then
    raise exception 'connect_four_column_full' using errcode = 'P0001';
  end if;

  insert into public.game_moves (session_id, move_number, player_id, move)
  values (p_session_id, v_played, v_me, p_column::text)
  returning public.game_moves.move_number into v_number;

  v_board := private.connect_four_board(p_session_id);
  v_winner := private.connect_four_winner(v_board);

  if v_winner <> 0 then
    v_winner_id := v_me;  -- whoever just moved is the only player who can have won
  else
    select count(*) into v_free from unnest(v_board) as cell where cell = 0;
    v_draw := v_free = 0;
  end if;

  if v_winner <> 0 or v_draw then
    update public.game_sessions
    set status = 'completed',
        completed_at = now(),
        updated_at = now(),
        -- Written here rather than left to be recomputed. It is recoverable for this game and not
        -- for chess, and one way of recording a result is better than two.
        winner_id = v_winner_id,
        outcome = case when v_winner <> 0 then 'win' else 'draw' end
    where id = p_session_id;
  end if;

  return query select v_number, (v_winner <> 0 or v_draw), v_winner_id, v_draw;
end;
$$;
