-- Daily job reminding couples who haven't answered today's Daily Activity question yet. Mirrors
-- the exact pg_cron + pg_net pattern already established by
-- 20260712170000_games_archive_cron_and_notif_prefs.sql (same Vault secrets, no new ones
-- needed). Scheduled at a single fixed UTC time (18:00) rather than per-user local time — this
-- app has no per-user timezone-aware scheduling infra yet, same simplicity tradeoff every other
-- cron job here already makes.

create or replace function private.trigger_send_streak_reminders()
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
    raise notice 'send-streak-reminders: project_url/service_role_key not set in Vault yet, skipping this run';
    return;
  end if;

  perform net.http_post(
    url := project_url || '/functions/v1/send-streak-reminders',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_key),
    body := '{}'::jsonb
  );
end;
$$;

select cron.schedule('send-streak-reminders', '0 18 * * *', 'select private.trigger_send_streak_reminders();');
