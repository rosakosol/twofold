-- `purge_couple_data` deletes by id and never asked what it was deleting.
--
-- Every caller means "this archive": the cron (`private.purge_expired_couple_archives`) and
-- `admin_purge_couple_archive`. The admin path checks `status = 'dissolved'` under a row lock first.
-- The cron does not: it reads its candidates with a plain SELECT and then calls this, and this ran
-- `delete from public.couples where id = $1`.
--
-- That loses a race with restore. `private.accept_connection_request` offers an archive while
-- `scheduled_purge_at > now()`, and `now()` is its transaction's start. A restore that begins a
-- moment before expiry and commits a moment after the cron's SELECT leaves the cron holding the id
-- of a couple that is, by the time it deletes, active again. Under READ COMMITTED the DELETE waits
-- for the restore's lock, re-checks only `id = $1`, and deletes the couple the two of them just
-- chose to keep — after this function had already queued every photo of theirs for R2. Rare;
-- unrecoverable when it happens.
--
-- So the purge checks for itself, under the lock, and does nothing to a couple that is not an
-- archive. Returning rather than raising: the cron purges several couples in one transaction, and
-- one restored in the meantime is not an error, just no longer its business. A couple that is not
-- found at all still runs the rest, as before, because delete-account and the cron both rely on a
-- repeated purge being harmless.
--
-- Body otherwise unchanged from 20261110000000.

create or replace function public.purge_couple_data(p_couple_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  select status::text into v_status from public.couples where id = p_couple_id for update;
  if found and v_status <> 'dissolved' then
    return;
  end if;

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

  delete from public.couples where id = p_couple_id and status = 'dissolved';
end;
$$;

-- `create or replace` keeps the existing ACL; restated so this file reads complete on its own.
revoke all on function public.purge_couple_data(uuid) from public, anon, authenticated;
grant execute on function public.purge_couple_data(uuid) to service_role;
