-- Root cause of "new row violates row-level security policy" persisting on avatar/partner-
-- avatar uploads (and drawing pad saves never actually persisting) even after the previous
-- migration's uuid-cast fix: the `avatars`/`drawing-pads` buckets had NO SELECT policy on
-- storage.objects at all. The actual INSERT/UPDATE succeeds fine (confirmed by direct testing
-- against the linked database, simulating the real authenticated user) — but the Storage API's
-- internal write then reads the row back (a `RETURNING`-style read-after-write) to build its
-- response, and that implicit read is itself subject to RLS. With zero SELECT policy on these
-- buckets, that read fails, and the whole request comes back as an RLS violation even though
-- the write itself was never the problem.
--
-- Both buckets are already `public: true` (objects are meant to be readable via the public URL
-- regardless of auth), so a public SELECT policy here doesn't change their security posture —
-- it just lets the same read succeed through the authenticated API path that the Storage
-- service uses internally after a write.

create policy "avatars_select_all" on storage.objects
  for select using (bucket_id = 'avatars');

create policy "drawing_pads_select_all" on storage.objects
  for select using (bucket_id = 'drawing-pads');
