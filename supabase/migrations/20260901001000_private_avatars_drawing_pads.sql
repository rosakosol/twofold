-- Closes a real privacy gap: `avatars` and `drawing-pads` were `public: true` buckets, meaning
-- anyone who ever obtained a profile/couple UUID (which show up in ordinary API responses all
-- over the app) could view that photo forever via an unauthenticated URL, with no way to revoke
-- access. Flip both to private, same as `memory-photos`/`flight-documents` already are, and
-- replace the blanket "any authenticated user" select policies with scoping that matches who
-- actually has a legitimate reason to see each image.

update storage.buckets set public = false where id in ('avatars', 'drawing-pads');

drop policy if exists "avatars_select_all" on storage.objects;
drop policy if exists "drawing_pads_select_all" on storage.objects;

-- avatars: folder is `{profileID}/...` — visible to that profile themself, their current
-- partner (mirrors `profiles_select_self_or_partner`), or the other party to a pending
-- connection request (mirrors the security-definer RPCs `fetch_my_outgoing_connection_request`/
-- `fetch_pending_connection_requests` already use to bridge pre-couple profile visibility).
create policy "avatars_select_self_or_partner" on storage.objects
  for select using (
    bucket_id = 'avatars'
    and (
      (storage.foldername(name))[1]::uuid = auth.uid()
      or exists (
        select 1 from public.couples
        where (partner_a_id = auth.uid() and partner_b_id = (storage.foldername(name))[1]::uuid)
           or (partner_b_id = auth.uid() and partner_a_id = (storage.foldername(name))[1]::uuid)
      )
    )
  );

create policy "avatars_select_connection_request_party" on storage.objects
  for select using (
    bucket_id = 'avatars'
    and exists (
      select 1 from public.connection_requests
      where (inviter_id = auth.uid() and requester_id = (storage.foldername(name))[1]::uuid)
         or (requester_id = auth.uid() and inviter_id = (storage.foldername(name))[1]::uuid)
    )
  );

-- Narrow, deliberately pre-auth exception: the invite-preview screens (JoinInviteView and
-- friends, reached from a cold deep-link tap before any account exists) show the inviter's name
-- *and avatar* via `get_invite_code_inviter_info`, which already exposes the name to anyone who
-- knows a still-pending, unexpired invite code. This grants the same narrow exposure to the
-- avatar image itself — a profile's avatar is only readable this way while they have an
-- outstanding pending invite, not permanently.
create policy "avatars_select_pending_inviter" on storage.objects
  for select using (
    bucket_id = 'avatars'
    and exists (
      select 1 from public.invite_codes
      where inviter_id = (storage.foldername(name))[1]::uuid
        and status = 'pending'
        and expires_at > now()
    )
  );

-- drawing-pads: folder is `{coupleID}/{personID}/...` — couple-membership scoped, same pattern
-- already used for memory-photos/flight-documents.
create policy "drawing_pads_select_members" on storage.objects
  for select using (
    bucket_id = 'drawing-pads'
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
  );
