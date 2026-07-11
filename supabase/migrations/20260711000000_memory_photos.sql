-- Memories move from a single photo_path column to a proper one-to-many photos table, so a
-- memory can hold multiple photos instead of just one. Existing single-photo rows are migrated
-- into the new table before the old column is dropped.
--
-- occurred_on (date-only) also becomes occurred_at (timestamptz) so the add/edit-memory time
-- picker has somewhere real to persist to, instead of silently discarding whatever time the
-- user picks.

alter table public.memories rename column occurred_on to occurred_at;
alter table public.memories alter column occurred_at type timestamptz using occurred_at::timestamptz;
alter table public.memories alter column occurred_at set default now();

create table public.memory_photos (
  id uuid primary key default gen_random_uuid(),
  memory_id uuid not null references public.memories (id) on delete cascade,
  photo_path text not null,
  position int not null default 0,
  created_at timestamptz not null default now()
);

create index memory_photos_memory_id_idx on public.memory_photos (memory_id);

insert into public.memory_photos (memory_id, photo_path, position)
select id, photo_path, 0 from public.memories where photo_path is not null;

alter table public.memories drop column photo_path;

alter table public.memory_photos enable row level security;

-- Same membership pattern as `memories` itself: readable/writable by either member of the
-- owning couple, gated to active couples for writes (mirrors memories_*_members_active).
create policy "memory_photos_select_members" on public.memory_photos
  for select using (
    exists (
      select 1 from public.memories m
      where m.id = memory_photos.memory_id and public.is_couple_member(m.couple_id)
    )
  );

create policy "memory_photos_insert_members_active" on public.memory_photos
  for insert with check (
    exists (
      select 1 from public.memories m
      where m.id = memory_photos.memory_id
        and public.is_couple_member(m.couple_id)
        and public.is_couple_active(m.couple_id)
    )
  );

create policy "memory_photos_delete_members_active" on public.memory_photos
  for delete using (
    exists (
      select 1 from public.memories m
      where m.id = memory_photos.memory_id
        and public.is_couple_member(m.couple_id)
        and public.is_couple_active(m.couple_id)
    )
  );
