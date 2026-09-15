-- Daily dormancy pass: warn, then close.
--
-- Same pg_cron + pg_net + Vault shape as every other scheduled job here (see
-- 20260713090000_streak_reminder_cron.sql). The policy lives in `public.dormancy_cohort`
-- (20261029000100) and the job in `purge-dormant-accounts`; this only decides when it runs.
--
-- 04:00 UTC, an hour after `reconcile-subscriptions`. Not for any subscription-related reason —
-- the dormancy timer deliberately ignores subscription state — but because two heavy jobs on the
-- same minute is how one of them starts timing out.
--
-- Daily, though the thing it measures moves in months. The windows are what need the frequency:
-- a warning window is seven days wide at its narrowest, and a weekly job that happened to miss it
-- would delete an account having sent only one of the two warnings.

create or replace function private.trigger_purge_dormant_accounts()
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
    raise notice 'purge-dormant-accounts: project_url/service_role_key not set in Vault yet, skipping this run';
    return;
  end if;

  perform net.http_post(
    url := project_url || '/functions/v1/purge-dormant-accounts',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_key),
    body := '{}'::jsonb
  );
end;
$$;

select cron.schedule('purge-dormant-accounts', '0 4 * * *', 'select private.trigger_purge_dormant_accounts();');
