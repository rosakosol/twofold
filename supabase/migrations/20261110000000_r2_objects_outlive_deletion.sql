-- Deleting an account leaves every photograph in R2, and after the purge we can no longer find them.
--
-- ---------------------------------------------------------------------------
-- What happens today
-- ---------------------------------------------------------------------------
--
-- `purge_couple_data` and `private.scrub_account` both delete rows from `storage.objects`. That was
-- right when the objects lived in Supabase Storage. Since the R2 migration they do not: the bytes
-- are in Cloudflare, keyed `{bucket}/{path}` where `path` is the string in `memory_photos
-- .photo_path`, `flight_documents.file_path`, `profiles.avatar_path` / `.partner_avatar_path`, or
-- the derived `{coupleID}/{personID}/pad.png` for a drawing pad. Nothing deletes those. Postgres
-- cannot reach R2, and `delete-account` contains no reference to it.
--
-- So a deleted account's avatar and drawing pads stay, and after the ninety-day archive purge every
-- memory photo and flight document stays. It is not an access-control hole — reaching an object
-- needs `can_access_storage_object`, which needs an `auth.uid()`, and a deleted account can never
-- sign in again — but it is unbounded retention, and three shipped statements say otherwise,
-- including the FAQ's "permanently deleted for both of you once it runs out".
--
-- ---------------------------------------------------------------------------
-- Why this is urgent rather than merely wrong
-- ---------------------------------------------------------------------------
--
-- `purge_couple_data` ends with `delete from public.couples`, which cascades `memories` and
-- therefore `memory_photos`, and `flights`/`trips` and therefore `flight_documents`. Those tables
-- are the only record of which objects belong to whom. `scripts/delete-r2-objects.ts` takes keys
-- rather than prefixes precisely because "every path is already recorded in the database", and
-- `_shared/r2.ts` has no list operation.
--
-- So every couple that passes ninety days moves from "we still have to delete these" to "we can no
-- longer work out what to delete". That is why the keys are captured here, before the cascade,
-- rather than in a cleanup written later.
--
-- ---------------------------------------------------------------------------
-- A durable queue, not a best-effort call
-- ---------------------------------------------------------------------------
--
-- `purge-support-attachments` deletes its rows first and accepts a failed R2 delete as a knowingly
-- logged leak. That is the right trade for a screenshot somebody abandoned: a few kilobytes nobody
-- can reach. It is the wrong trade here, where the object is a photograph somebody asked us to
-- delete and the row that named it is about to be gone forever.
--
-- So the keys go into a table that outlives both the transaction and the row, and a key leaves it
-- only when R2 has confirmed the object is gone. A failure is a retry, not a leak.
--
-- This does nothing for objects already stranded by deletions that have run since the R2 migration.
-- Their paths are gone and only a bucket listing will find them; `scripts/delete-r2-objects.ts`
-- exists for that and needs a listing this codebase cannot perform.

-- ---------------------------------------------------------------------------
-- The queue
-- ---------------------------------------------------------------------------

create table if not exists public.pending_object_deletions (
  -- The full R2 key, prefix included, exactly as `presign` wants it. Primary key so a couple
  -- purged twice — or a retried `delete-account` — enqueues once.
  key text primary key,
  enqueued_at timestamptz not null default now(),
  attempts integer not null default 0,
  last_error text
);

comment on table public.pending_object_deletions is
  'R2 keys whose objects must be deleted. Written by the purge functions before the rows naming '
  'those objects are cascaded away; drained by the purge-r2-objects function. A row leaves only '
  'when R2 has confirmed the object is gone, so a failed delete retries rather than leaking.';

-- Deny-all, matching the other nine service-role-only tables: RLS on, no policies. The blanket
-- grants from 20260911000100 mean this is the only thing standing between a client and the queue.
alter table public.pending_object_deletions enable row level security;

-- ---------------------------------------------------------------------------
-- Collecting the keys
-- ---------------------------------------------------------------------------

create or replace function private.enqueue_object_deletions(p_keys text[])
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.pending_object_deletions (key)
  select distinct k from unnest(p_keys) as k
  where k is not null and k <> ''
  on conflict (key) do nothing;
$$;

-- Every R2 object belonging to a couple: photos, flight documents, and both partners' pads.
--
-- A flight document hangs off either a flight or a trip — `flight_documents` carries both columns
-- and the privacy tests exercise a dual-parent row — so both routes to `couple_id` are followed.
-- Drawing pads have no column anywhere; the path is derived, so it is derived here too, from the
-- couple row that is about to be deleted.
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
  where m.couple_id = p_couple_id and mp.photo_path is not null

  union

  select 'flight-documents/' || fd.file_path
  from public.flight_documents fd
  left join public.flights f on f.id = fd.flight_id
  left join public.trips t on t.id = fd.trip_id
  where fd.file_path is not null
    and (f.couple_id = p_couple_id or t.couple_id = p_couple_id)

  union

  select 'drawing-pads/' || p_couple_id::text || '/' || partner || '/pad.png'
  from (
    select c.partner_a_id::text as partner from public.couples c where c.id = p_couple_id
    union
    select c.partner_b_id::text from public.couples c where c.id = p_couple_id
  ) partners
  where partner is not null;
$$;

-- The objects a single profile owns outright, independent of any couple.
--
-- `partner_avatar_path` is included because it is a file *this* profile uploaded — their own guess
-- at their partner's photo, stored under their own id — not the partner's avatar.
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
  where path is not null and path <> ''

  union

  -- Pads this person drew, in whatever couples they have belonged to. Matches what the existing
  -- `storage.objects` delete did: it keyed on the second path segment, which is the person.
  select 'drawing-pads/' || c.id::text || '/' || p_profile_id::text || '/pad.png'
  from public.couples c
  where c.partner_a_id = p_profile_id or c.partner_b_id = p_profile_id;
$$;

-- ---------------------------------------------------------------------------
-- The two purge paths, now capturing before they destroy
-- ---------------------------------------------------------------------------

-- Body otherwise unchanged from 20260901001900. The `storage.objects` deletes are kept: the
-- originals from before the R2 migration are still in those buckets during the soak, and removing
-- their rows is what the function has always done. See the backlog on that being its own problem —
-- deleting the row strands the file — which is a separate decision from this one.
create or replace function public.purge_couple_data(p_couple_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- First, and before anything cascades: `delete from public.couples` below takes `memories` and
  -- `memory_photos` with it, and those rows are the only record of which R2 objects were this
  -- couple's. Captured here, they outlive the cascade.
  perform private.enqueue_object_deletions(
    array(select private.couple_object_keys(p_couple_id))
  );

  -- Storage objects aren't FK-linked to couples, so they have to go explicitly. Everything
  -- else (trips, memories, flights + their events/prefs/documents, game sessions + rounds +
  -- responses) is `on delete cascade` back to couples.id, so deleting the couple row is enough.
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects where bucket_id = 'memory-photos' and (storage.foldername(name))[1] = p_couple_id::text;
  delete from storage.objects where bucket_id = 'flight-documents' and (storage.foldername(name))[1] = p_couple_id::text;
  delete from storage.objects where bucket_id = 'drawing-pads' and (storage.foldername(name))[1] = p_couple_id::text;

  delete from public.couples where id = p_couple_id;
end;
$$;

-- Body otherwise unchanged from 20261109000900. The enqueue goes at the top for the same reason as
-- above, and specifically before the `update public.profiles` at the end, which nulls `avatar_path`
-- and `partner_avatar_path` — the only record of those two keys.
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

  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects where bucket_id = 'avatars' and (storage.foldername(name))[1] = p_profile_id::text;
  delete from storage.objects where bucket_id = 'drawing-pads' and (storage.foldername(name))[2] = p_profile_id::text;

  delete from public.device_push_tokens where profile_id = p_profile_id;
  delete from public.live_activity_push_tokens where profile_id = p_profile_id;

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

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
--
-- All three roles named, every time. Supabase's default privileges hand anon and authenticated an
-- explicit EXECUTE on each new function, so `revoke ... from public` alone leaves the function
-- callable by exactly the roles being locked out — the mechanism 20261108000000 exists to undo, and
-- the reason `purge_couple_data` itself was reachable by anon until that migration.
revoke all on function private.enqueue_object_deletions(text[]) from public, anon, authenticated;
revoke all on function private.couple_object_keys(uuid) from public, anon, authenticated;
revoke all on function private.profile_object_keys(uuid) from public, anon, authenticated;

-- The drain reads and deletes rows as service_role, which bypasses RLS; stated rather than left to
-- the blanket grant so removing that grant later does not silently break the queue.
grant select, update, delete on public.pending_object_deletions to service_role;
