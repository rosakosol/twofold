-- The soak has ended, and the legacy buckets were still writable the whole way through it.
--
-- `scripts/copy-storage-to-r2.ts` says it plainly: "Nothing is deleted from Supabase Storage. That
-- stays as it is until the new build has been running for a while." What a soak needs is reads —
-- the ability to go back and fetch an original if something turned out wrong. It never needed
-- writes, and nothing in the app has written to Supabase Storage since the migration: every upload
-- goes through `storage-url` and `presign` to R2.
--
-- So these six policies have been accepting uploads that no code produces, into buckets with no
-- MIME allowlist and no per-bucket size limit, from any signed-in user under their own prefix, at
-- our expense. That is not an access-control hole — the paths are still couple-scoped — it is free
-- hosting nobody is watching, in a place nobody looks any more.
--
-- Dropped rather than narrowed, because there is no correct narrower version: the right number of
-- writes to a retired bucket is none.
--
-- The select policies stay. Deleting the objects themselves is a separate step and has to go
-- through the Storage API rather than through this table — `storage.protect_delete()` exists
-- precisely because removing a row strands the file it pointed at, and `storage.objects.version`
-- is the only thing that maps a row to its backing key. `scripts/delete-storage-originals.ts` does
-- it the supported way, and checks each object exists in R2 before removing the original, which is
-- the question the soak was actually asking.

drop policy if exists "avatars_insert_own" on storage.objects;
drop policy if exists "avatars_update_own" on storage.objects;
drop policy if exists "drawing_pads_insert_own" on storage.objects;
drop policy if exists "drawing_pads_update_own" on storage.objects;
drop policy if exists "flight_documents_storage_insert_members_active" on storage.objects;
drop policy if exists "memory_photos_insert_members_active" on storage.objects;
