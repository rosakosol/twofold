-- New opt-in notification type: a final "1 hour left" nudge before the daily streak actually
-- lapses, distinct from the existing end-of-day daily_streak_reminder (18:00 UTC) so a couple can
-- turn the last-chance ping off independently of the earlier one. Same toggle pattern as every
-- other column on this table — missing row still means "on" (default true).
alter table public.notification_preferences
  add column streak_ending_reminder boolean not null default true;

-- Same pg_cron + pg_net pattern as 20260713090000_streak_reminder_cron.sql's
-- trigger_send_streak_reminders(), just posting `{"final": true}` so send-streak-reminders
-- knows to use the "1 hour left" copy and gate on streak_ending_reminder instead of
-- daily_streak_reminder. Scheduled at 23:00 UTC — the streak's own day boundary is midnight UTC
-- (see send-streak-reminders' own todayStart), so this is genuinely "1 hour before it runs out",
-- not an arbitrary later time.
create or replace function private.trigger_send_streak_ending_reminders()
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
    raise notice 'send-streak-reminders (final): project_url/service_role_key not set in Vault yet, skipping this run';
    return;
  end if;

  perform net.http_post(
    url := project_url || '/functions/v1/send-streak-reminders',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_key),
    body := '{"final": true}'::jsonb
  );
end;
$$;

select cron.schedule('send-streak-ending-reminders', '0 23 * * *', 'select private.trigger_send_streak_ending_reminders();');
