-- PostgREST runs pgrst.db_pre_request as the caller's own role, on every request, and that includes
-- service_role. 20261114005000 granted the hook to anon and authenticated only, so whether the server
-- could call the API at all rested on Supabase's default function grants. On a fresh local replay it
-- could not: every service-role call failed with permission denied. Say it outright instead.
--
-- For service_role the hook does nothing: auth.uid() is null, so no account is looked up.
grant execute on function public.reject_deleted_accounts() to service_role;
