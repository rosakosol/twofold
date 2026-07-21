-- Bootstraps kosolrosa@gmail.com (the real account owner, now signed in via Google
-- through the deployed feedback app) as a feedback admin — the one existing
-- feedback_admins row was from a different test account earlier in development.
insert into public.feedback_admins (profile_id)
values ('30d7af65-8717-4a7d-b465-b0848d8a08d6')
on conflict (profile_id) do nothing;

drop function if exists public.debug_check_admin_status(text);
drop function if exists public.debug_check_profile_exists(uuid);
