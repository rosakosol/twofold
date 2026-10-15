-- `can_access_storage_object` knew about couples and nothing that has been added on top of them.
--
-- 20261030000000 transcribed the Storage policies as they stood. Two rules the rest of the schema
-- enforces were never in those policies, so they are not in the function either, and the function
-- is now the only thing between a caller and a presigned URL R2 will honour for anyone.
--
-- ---------------------------------------------------------------------------
-- 1. A private flight's documents
-- ---------------------------------------------------------------------------
--
-- `flights.shared = false` hides a flight and every row hanging off it from the partner —
-- `flight_documents_select_members` goes through `can_see_flight` (20260916000000). The object
-- behind a document row did not: `flight-documents/{coupleID}/{flightID}/{uuid}` was readable,
-- overwritable and deletable by either member on the strength of the first segment alone. So a
-- boarding pass (full name, PNR, frequent-flyer number) on a flight its owner chose to keep private
-- was one known path away from the partner — a path they already hold if the flight was ever
-- shared and its documents opened, since a cached `file_path` outlives the visibility of its row.
--
-- The rule added is narrow on purpose: when the parent segment names a flight in this couple, the
-- caller must be able to see that flight. Anything else falls through to the old membership rule
-- unchanged — a trip (trips have no privacy toggle), and a flight that no longer exists, which is
-- the normal case for `deleteFlight`: it deletes the row first and removes the objects after, so
-- refusing an absent parent would strand every document of every deleted flight.
--
-- ---------------------------------------------------------------------------
-- 2. A block, for avatars
-- ---------------------------------------------------------------------------
--
-- Avatar paths are not secrets — `{ownerID}/avatar.jpg`, fixed, built in `BackendService` — so the
-- read branch is the whole of the protection. It opens on any couple row ever shared (dissolved
-- ones included, until the 90-day purge removes them), any connection request ever exchanged
-- (declined ones included, forever), and any pending invite. A person who blocked someone therefore
-- kept handing that someone every new photo of themselves, which is precisely the contact a block
-- exists to end (20261023000000).
--
-- Directional: the owner having blocked the caller closes the read. The reverse does not — blocking
-- someone should not blank their face out of your own archive. And it is the one refusal the
-- blocked person can observe only as a missing photo, which is what any failed load looks like;
-- it says nothing a 403 for an expired invite would not.
--
-- ---------------------------------------------------------------------------
-- 3. Drawing pads stop taking writes when the couple does
-- ---------------------------------------------------------------------------
--
-- Memory photos and flight documents both need an active couple to write. Pads did not, so after a
-- disconnection — or a block, which disconnects — either side could keep drawing into a pad the
-- other still reads for the archive's lifetime. Brought into line with the other two.
--
-- Everything else is carried over from 20261030000000 verbatim.

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

-- `create or replace` keeps the existing ACL, so these change nothing today. Restated because the
-- grant is part of the function's contract and 20261108000000 is where it was last fixed: execute
-- for `authenticated` alone, never `PUBLIC`.
revoke all on function public.can_access_storage_object(text, text, text) from public, anon;
grant execute on function public.can_access_storage_object(text, text, text) to authenticated;
