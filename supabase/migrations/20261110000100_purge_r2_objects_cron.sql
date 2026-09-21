-- Drains `pending_object_deletions` on a schedule.
--
-- The queue fills in 20261110000000, whenever an account is scrubbed or a couple's archive is
-- purged. This is the half that reaches Cloudflare.
--
-- ---------------------------------------------------------------------------
-- Scheduled, but not enabled to delete anything yet
-- ---------------------------------------------------------------------------
--
-- The job is created **unscheduled on purpose**: `cron.schedule` is called and then immediately
-- `cron.alter_job(..., active => false)`. It does not run until somebody turns it on.
--
-- That is not caution for its own sake. Every other deletion in this codebase removes something
-- the person in front of it just asked to remove. This one deletes photographs on a timer, from a
-- list assembled by a function whose first production run will be its first run at all, and a
-- collector that was too greedy would take a stranger's memories rather than leaving rubbish in a
-- bucket. Of the two ways to be wrong, only one is unrecoverable, and it is not the one this
-- migration was written to fix.
--
-- So: let the queue fill for a day, read it back with
--
--   curl -X POST "$PROJECT_URL/functions/v1/purge-r2-objects" \
--     -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
--     -H 'Content-Type: application/json' --data '{"dryRun": true}'
--
-- check the keys against a couple you control, then
--
--   select cron.alter_job((select jobid from cron.job where jobname = 'purge-r2-objects'),
--                         active => true);
--
-- Nothing is lost while it is off. Keys accumulate; they are only removed on a confirmed delete.

create or replace function private.trigger_purge_r2_objects()
returns void
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare
  project_url text;
  service_key text;
begin
  select decrypted_secret into project_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into service_key from vault.decrypted_secrets where name = 'service_role_key';

  if project_url is null or service_key is null then
    raise notice 'purge-r2-objects: project_url/service_role_key not set in Vault yet, skipping this run';
    return;
  end if;

  perform net.http_post(
    url := project_url || '/functions/v1/purge-r2-objects',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_key),
    body := '{}'::jsonb
  );
end;
$$;

revoke all on function private.trigger_purge_r2_objects() from public, anon, authenticated;

-- 04:15. The archive purge that fills this queue runs at 03:00 and the support-attachment purge at
-- 03:45, so this sits after both rather than racing the job that produces its work.
--
-- One batch of 500 per run. A couple with a decade of photographs exceeds that, which is fine:
-- what is left stays queued and the next run takes it. Nothing about this is urgent once the keys
-- are safely captured — the point of the queue was never speed.
select cron.schedule(
  'purge-r2-objects',
  '15 4 * * *',
  'select private.trigger_purge_r2_objects();'
);

select cron.alter_job(
  (select jobid from cron.job where jobname = 'purge-r2-objects'),
  active => false
);
