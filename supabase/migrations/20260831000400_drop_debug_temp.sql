delete from public.waitlist_signups where email = 'verify-prod-deploy-3@example.com';
drop function if exists public.debug_check_waitlist_row(text);
drop function if exists public.debug_waitlist_count();
