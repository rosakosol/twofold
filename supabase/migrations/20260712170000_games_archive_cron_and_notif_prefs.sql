-- Daily job to archive stale game sessions where the invited partner never joined at all — a
-- session sitting in 'active' for days with zero responses from the non-initiating partner just
-- clutters the "waiting" list forever otherwise. Mirrors the exact pg_cron + pg_net pattern
-- already established by 20260712000100_flight_refresh_cron.sql (same Vault secrets, already
-- provisioned — no new secrets needed).

create or replace function private.trigger_archive_stale_games()
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
    raise notice 'archive-stale-games: project_url/service_role_key not set in Vault yet, skipping this run';
    return;
  end if;

  perform net.http_post(
    url := project_url || '/functions/v1/archive-stale-games',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_key),
    body := '{}'::jsonb
  );
end;
$$;

select cron.schedule('archive-stale-games', '0 6 * * *', 'select private.trigger_archive_stale_games();');

-- New notification type: "your results are ready" (both partners just finished). Same toggle
-- pattern as the other 4 columns in this table.
alter table public.notification_preferences
  add column partner_game_results_ready boolean not null default true;
