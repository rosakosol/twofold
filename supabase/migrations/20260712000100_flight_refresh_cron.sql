-- Scheduled flight polling: pg_cron fires every 5 minutes and asks the
-- `refresh-due-flights` Edge Function to refresh whatever is actually due per its own
-- tiered cadence (far-out flights are skipped most runs; active/near-departure flights are
-- refreshed every run). The cron job itself is cheap and simple; all the interval logic
-- lives in the function.
--
-- Requires two one-time secrets in Supabase Vault (SQL Editor, run once after this
-- migration — the service role key must never live in a migration file):
--   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
--   select vault.create_secret('<service role key from Project Settings -> API>', 'service_role_key');

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

create schema if not exists private;

create or replace function private.trigger_refresh_due_flights()
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
    raise notice 'refresh-due-flights: project_url/service_role_key not set in Vault yet, skipping this run';
    return;
  end if;

  perform net.http_post(
    url := project_url || '/functions/v1/refresh-due-flights',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_key),
    body := '{}'::jsonb
  );
end;
$$;

select cron.schedule('refresh-due-flights', '*/5 * * * *', 'select private.trigger_refresh_due_flights();');
