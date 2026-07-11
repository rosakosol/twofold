-- Home-screen doodle pad: one PNG per person, at a fixed deterministic path
-- {couple_id}/{person_id}/pad.png — no separate DB table needed, the app just constructs the
-- path directly. Public bucket (a casual doodle isn't sensitive), same convention as avatars.

insert into storage.buckets (id, name, public)
values ('drawing-pads', 'drawing-pads', true)
on conflict (id) do nothing;

create policy "drawing_pads_insert_own" on storage.objects
  for insert with check (
    bucket_id = 'drawing-pads'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

create policy "drawing_pads_update_own" on storage.objects
  for update using (
    bucket_id = 'drawing-pads'
    and (storage.foldername(name))[2] = auth.uid()::text
  );
