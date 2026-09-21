-- ---------------------------------------------------------------------------
-- Collecting files whose reply was never sent
-- ---------------------------------------------------------------------------
--
-- `private.purge_dangling_support_attachments` deletes the rows and hands back the keys, because
-- Postgres cannot reach R2. Until something actually calls it, an attachment somebody uploaded and
-- then abandoned — picked a screenshot, changed their mind, closed the tab — stays in the bucket
-- forever with nothing pointing at it.
--
-- Unlike the usage rollup this cannot be pure SQL: the job has to delete objects in another system,
-- so it goes through an edge function like the other jobs that reach outside the database.
--
-- ---------------------------------------------------------------------------
-- Rows first, objects second
-- ---------------------------------------------------------------------------
--
-- The order is deliberate and the failure modes are not symmetric. A row deleted whose object
-- survives is a few kilobytes nobody can reach — a leak, and a small one. An object deleted whose
-- row survives is an attachment the console lists and the send cannot fetch, which fails a reply
-- at the moment somebody is trying to answer a customer.
--
-- So the rows go first, and if the R2 deletes fail the next run simply does not see those keys
-- again. That is the leak, accepted knowingly, and the function logs each failure so a bucket
-- filling up is visible rather than mysterious.

-- `private` is not served over PostgREST, so the edge function needs a door in `public`.
-- service_role only: this deletes rows, and the caller is a cron job holding the service key.
create or replace function public.purge_dangling_support_attachments(p_older_than_hours integer default 24)
returns table (r2_key text)
language plpgsql
security definer
set search_path = private, public, auth
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  return query
    select * from private.purge_dangling_support_attachments(
      make_interval(hours => greatest(coalesce(p_older_than_hours, 24), 1))
    );
end;
$$;

revoke execute on function public.purge_dangling_support_attachments(integer)
  from public, anon, authenticated;
grant execute on function public.purge_dangling_support_attachments(integer) to service_role;

-- Same pg_cron + pg_net + Vault shape as every other job that calls an edge function; see
-- 20260713090000_streak_reminder_cron.sql for the original.
create or replace function private.trigger_purge_support_attachments()
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
    raise notice 'purge-support-attachments: project_url/service_role_key not set in Vault yet, skipping this run';
    return;
  end if;

  perform net.http_post(
    url := project_url || '/functions/v1/purge-support-attachments',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_key),
    body := '{}'::jsonb
  );
end;
$$;

-- 03:45. Every other daily job sits on the hour or the half hour, and the dormancy migration's note
-- applies here as it does everywhere: two heavy jobs on one minute is how one of them starts timing
-- out. This one is neither heavy nor urgent — it collects files nobody is waiting for.
select cron.schedule(
  'purge-support-attachments',
  '45 3 * * *',
  'select private.trigger_purge_support_attachments();'
);
