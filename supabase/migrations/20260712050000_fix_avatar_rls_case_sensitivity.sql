-- Root cause of "new row violates row-level security policy" on every avatar/partner-avatar
-- upload: Swift's `"\(userID)"` UUID string interpolation produces an UPPERCASE UUID string
-- (`UUID.uuidString`), while Postgres's `auth.uid()::text` always renders lowercase. The
-- policies below compared the storage folder name against `auth.uid()::text` as raw text, which
-- is case-sensitive — so the check silently failed for every upload, self or partner.
--
-- Fix: cast the folder-name segment to `uuid` instead of comparing as `text`. uuid equality is
-- case-insensitive, so this matches regardless of how the client formats the id — the same
-- pattern already used safely by the flight-documents/memory-photos policies
-- (`((storage.foldername(name))[1])::uuid = auth.uid()`). Also fixes the identical latent bug
-- in the drawing-pads policies (not yet reported, but the same construction).

drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own" on storage.objects
  for insert with check (
    bucket_id = 'avatars'
    and ((storage.foldername(name))[1])::uuid = auth.uid()
  );

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own" on storage.objects
  for update using (
    bucket_id = 'avatars'
    and ((storage.foldername(name))[1])::uuid = auth.uid()
  );

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own" on storage.objects
  for delete using (
    bucket_id = 'avatars'
    and ((storage.foldername(name))[1])::uuid = auth.uid()
  );

drop policy if exists "drawing_pads_insert_own" on storage.objects;
create policy "drawing_pads_insert_own" on storage.objects
  for insert with check (
    bucket_id = 'drawing-pads'
    and ((storage.foldername(name))[2])::uuid = auth.uid()
  );

drop policy if exists "drawing_pads_update_own" on storage.objects;
create policy "drawing_pads_update_own" on storage.objects
  for update using (
    bucket_id = 'drawing-pads'
    and ((storage.foldername(name))[2])::uuid = auth.uid()
  );
