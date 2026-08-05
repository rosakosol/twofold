-- Bootstraps kosolrosa@gmail.com (the real account owner, now signed in via Google
-- through the deployed feedback app) as a feedback admin — the one existing
-- feedback_admins row was from a different test account earlier in development.
-- Guarded with `where exists` (rather than a bare `values` insert) so this stays a no-op
-- on a fresh database — a plain insert 23503s on the profiles FK when this profile row
-- doesn't exist yet (a new local/CI/staging environment, before anyone's signed up),
-- which previously broke replaying the migration chain from scratch.
insert into public.feedback_admins (profile_id)
select '30d7af65-8717-4a7d-b465-b0848d8a08d6'
where exists (select 1 from public.profiles where id = '30d7af65-8717-4a7d-b465-b0848d8a08d6')
on conflict (profile_id) do nothing;

drop function if exists public.debug_check_admin_status(text);
drop function if exists public.debug_check_profile_exists(uuid);
