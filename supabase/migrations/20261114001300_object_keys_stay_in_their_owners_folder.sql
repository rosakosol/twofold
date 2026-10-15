-- Two fixes to the R2 key collectors from 20261110000000, which decide what `purge-r2-objects`
-- deletes without a second look.
--
-- ---------------------------------------------------------------------------
-- 1. A path column is somebody's claim, not proof of ownership
-- ---------------------------------------------------------------------------
--
-- `profiles.avatar_path` / `.partner_avatar_path` are client-writable on the caller's own row, and
-- `memory_photos.photo_path` / `flight_documents.file_path` are client-insertable by any member of
-- the parent's couple. None has a constraint on what it names. The collectors prefixed the bucket
-- and queued whatever was there, so:
--
--   * set your own avatar_path to your partner's `{theirID}/avatar.jpg` (readable to you), delete
--     your account, and their photo is deleted from R2 on the next run;
--   * as an ex-partner, insert a memory_photos row into your new couple carrying a path from the
--     old one (still readable to you in its archive), and when the new couple is purged the old
--     couple's photograph goes with it — even if the other two restored it in the meantime.
--
-- `storage-url` never had this problem: `can_access_storage_object` takes the owning id from the
-- path's first segment and checks it. The collectors now hold the same line — the first segment is
-- the profile (for avatars) or the couple (for photos and documents), and no segment is empty,
-- `.` or `..` — and simply leave out anything else. Leaving a stray key out leaks one object; queuing
-- it deletes somebody's photograph. Of the two ways to be wrong here, only one is recoverable.
--
-- Compared case-insensitively, because the app writes Swift `UUID` interpolations, which are
-- uppercase, and `uuid::text` is lowercase.
--
-- ---------------------------------------------------------------------------
-- 2. Drawing pads were queued under a key that does not exist
-- ---------------------------------------------------------------------------
--
-- Pads have no path column, so both collectors rebuild `drawing-pads/{couple}/{person}/pad.png`
-- from ids — in lowercase. The app uploads `"\(coupleID)/\(personID)/pad.png"` from Swift UUIDs
-- (BackendService.drawingPadPath), which is uppercase. R2 keys are case-sensitive, the DELETE
-- answers 404, and `purge-r2-objects` reads 404 as "already gone" and dequeues it. So no pad has
-- ever been deleted, by an account deletion or by a purge, and the queue reports success.
--
-- Both forms are queued now. The uppercase one is what the app writes; the lowercase one costs a
-- 404 and covers anything that ever wrote the canonical form. Queued keys for pads already lost
-- this way cannot be recovered from here — the couples they belonged to are gone — and need a
-- bucket listing to find.

create or replace function private.is_owned_object_path(p_path text, p_owner uuid)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_path is not null
    and p_owner is not null
    and lower(split_part(p_path, '/', 1)) = p_owner::text
    and not exists (
      select 1 from unnest(string_to_array(p_path, '/')) as segment
      where segment in ('', '.', '..')
    );
$$;

revoke all on function private.is_owned_object_path(text, uuid) from public, anon, authenticated;

create or replace function private.couple_object_keys(p_couple_id uuid)
returns setof text
language sql
stable
security definer
set search_path = public
as $$
  select 'memory-photos/' || mp.photo_path
  from public.memory_photos mp
  join public.memories m on m.id = mp.memory_id
  where m.couple_id = p_couple_id
    and private.is_owned_object_path(mp.photo_path, p_couple_id)

  union

  select 'flight-documents/' || fd.file_path
  from public.flight_documents fd
  left join public.flights f on f.id = fd.flight_id
  left join public.trips t on t.id = fd.trip_id
  where (f.couple_id = p_couple_id or t.couple_id = p_couple_id)
    and private.is_owned_object_path(fd.file_path, p_couple_id)

  union

  select 'drawing-pads/' || ids.couple || '/' || ids.partner || '/pad.png'
  from public.couples c
  cross join lateral (values (c.partner_a_id), (c.partner_b_id)) as p(partner_id)
  cross join lateral (values
    (upper(c.id::text), upper(p.partner_id::text)),
    (c.id::text, p.partner_id::text)
  ) as ids(couple, partner)
  where c.id = p_couple_id and p.partner_id is not null;
$$;

create or replace function private.profile_object_keys(p_profile_id uuid)
returns setof text
language sql
stable
security definer
set search_path = public
as $$
  select 'avatars/' || path
  from (
    select avatar_path as path from public.profiles where id = p_profile_id
    union
    select partner_avatar_path from public.profiles where id = p_profile_id
  ) paths
  where private.is_owned_object_path(path, p_profile_id)

  union

  -- Pads this person drew, in whatever couples they have belonged to.
  select 'drawing-pads/' || ids.couple || '/' || ids.person || '/pad.png'
  from public.couples c
  cross join lateral (values
    (upper(c.id::text), upper(p_profile_id::text)),
    (c.id::text, p_profile_id::text)
  ) as ids(couple, person)
  where c.partner_a_id = p_profile_id or c.partner_b_id = p_profile_id;
$$;

revoke all on function private.couple_object_keys(uuid) from public, anon, authenticated;
revoke all on function private.profile_object_keys(uuid) from public, anon, authenticated;
