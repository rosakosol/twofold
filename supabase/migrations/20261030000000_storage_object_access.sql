-- Who may read or write a stored object, as a function rather than as Storage policies.
--
-- Object storage is moving from Supabase Storage to Cloudflare R2. R2 has no RLS: it authorises
-- by signature alone, so anything holding a presigned URL can fetch. The authorisation therefore
-- has to happen *before* the URL is minted, in the Edge Function that mints it — and if that
-- function reimplemented the rules in TypeScript, there would be two copies of them and only one
-- would be tested.
--
-- So the rules move here, as close to the RLS they replace as they can get, and the Edge Function
-- becomes a thin presigner that asks this one question. `storage_object_access_test.sql` pins
-- every branch, which the TypeScript version could not have been.
--
-- Each branch below is the storage policy it replaces, transcribed. For the record, those were:
--
--   avatars           select: self, or partner, or connection-request counterparty, or *anyone*
--                             when the owner has a pending unexpired invite code
--                     insert/update/delete: foldername[1] = auth.uid()
--   drawing-pads      select: is_couple_member(foldername[1])
--                     insert/update: foldername[2] = auth.uid()   (no delete policy at all)
--   memory-photos     select: is_couple_member(foldername[1])
--                     insert/delete: is_couple_member AND is_couple_active
--   flight-documents  select/delete: is_couple_member(foldername[1])
--                     insert: is_couple_member AND is_couple_active
--
-- The one deliberate departure is that this is stricter about shape. The policies only ever looked
-- at one path segment and ignored the rest, so a path with the right prefix and any tail passed.
-- Here each kind must have exactly the number of segments the app actually produces. Paths are
-- built in exactly four places in `BackendService`, all of them fixed shapes, so nothing legitimate
-- is turned away — and a key is a flat string in R2, with no filesystem to normalise `..` away.

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
begin
  -- Anonymous callers get nothing. Every bucket this covers is private; the only public one is
  -- airline logos, which is not a `p_kind` here because there is nothing to authorise.
  if v_uid is null or p_kind is null or p_path is null or p_op is null then
    return false;
  end if;

  if p_op not in ('read', 'write', 'delete') then
    return false;
  end if;

  v_parts := string_to_array(p_path, '/');

  -- An empty or relative segment means a caller is constructing paths rather than passing one the
  -- app built. Rejected before any of it is parsed, so `a//b` and `couple/../other` never reach a
  -- prefix check that would read the wrong segment as the couple id.
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

      -- Reads are wider than the other three kinds, and deliberately so: an invite screen shows a
      -- face before there is any couple to be a member of. The last clause is open to every signed
      -- in caller, not just one counterparty — that is what the policy did, and narrowing it here
      -- would blank the avatar on the join-invite screen.
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

      -- There was never a delete policy on this bucket: a pad is overwritten in place, never
      -- removed, and the widget relies on that path staying resolvable. Saying no here keeps it so.
      if p_op = 'delete' then return false; end if;
      -- Only your own pad, and only in a couple you belong to. The policy checked just the second
      -- segment; requiring membership too costs nothing and stops a pad being written into a
      -- stranger's couple prefix under your own id.
      if p_op = 'write' then return v_person = v_uid and is_couple_member(v_couple); end if;
      return is_couple_member(v_couple);

    -- memory-photos/{coupleID}/{memoryID}/{uuid}.jpg
    when 'memory-photo' then
      if coalesce(array_length(v_parts, 1), 0) <> 3 then return false; end if;
      begin
        v_couple := v_parts[1]::uuid;
      exception when invalid_text_representation then
        return false;
      end;
      -- Reading stays available to a dissolved couple, because their archive is still theirs to
      -- read and export. Changing it does not.
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
      -- Asymmetric, matching the policies: adding a document needs an active couple, removing one
      -- does not, so a dissolved couple can still tidy up.
      if p_op = 'write' then return is_couple_member(v_couple) and is_couple_active(v_couple); end if;
      return is_couple_member(v_couple);

    else
      -- An unknown kind is a bug in the caller, and the safe answer to a question nobody defined
      -- is no.
      return false;
  end case;
end;
$$;

revoke all on function public.can_access_storage_object(text, text, text) from public;
grant execute on function public.can_access_storage_object(text, text, text) to authenticated;
