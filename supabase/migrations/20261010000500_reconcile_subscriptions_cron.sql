-- Nightly subscription reconciliation.
--
-- Every subscription column on `profiles` is written by webhook delivery alone. Nothing re-reads
-- RevenueCat, so a delivery that is missed, dropped or never sent leaves a row wrong permanently:
-- a lapse that never arrives keeps someone's access alive, and a renewal that never arrives
-- paywalls someone who is paying. `subscription_checked_at` only guards against a stale write
-- landing after a fresher one; it cannot notice that no write ever came.
--
-- Confirmed rather than theoretical: every one of the seven active subscribers at the time of
-- writing had a `subscription_checked_at` frozen at whenever their last delivery happened, some of
-- them weeks earlier, with no mechanism that would ever refresh them.
--
-- Same pg_cron + pg_net + Vault shape as every other scheduled job here (see
-- 20260713090000_streak_reminder_cron.sql). 03:00 UTC: nothing else is scheduled then, and a
-- correction landing overnight is one nobody watches happen.

create or replace function private.trigger_reconcile_subscriptions()
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
    raise notice 'reconcile-subscriptions: project_url/service_role_key not set in Vault yet, skipping this run';
    return;
  end if;

  perform net.http_post(
    url := project_url || '/functions/v1/reconcile-subscriptions',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_key),
    body := '{}'::jsonb
  );
end;
$$;

select cron.schedule('reconcile-subscriptions', '0 3 * * *', 'select private.trigger_reconcile_subscriptions();');
