-- Daily job nudging still-solo users (signed up but no active couple yet) to invite their
-- partner. Mirrors the exact pg_cron + pg_net pattern already established by
-- 20260713090000_streak_reminder_cron.sql (same Vault secrets, no new ones needed). Scheduled at
-- a fixed UTC time distinct from the streak-reminder job so both aren't hitting pg_net at the
-- exact same minute, though that wouldn't actually matter functionally.
create or replace function private.trigger_send_partner_invite_reminders()
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
    raise notice 'send-partner-invite-reminders: project_url/service_role_key not set in Vault yet, skipping this run';
    return;
  end if;

  perform net.http_post(
    url := project_url || '/functions/v1/send-partner-invite-reminders',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_key),
    body := '{}'::jsonb
  );
end;
$$;

select cron.schedule('send-partner-invite-reminders', '0 14 * * *', 'select private.trigger_send_partner_invite_reminders();');
