-- Gives the website's support form the id of the conversation a request lands in (SITE-18).
--
-- The receipt a visitor gets quotes a ticket reference, and that reference matched nothing in the
-- console. The route made up six random characters, because submit_support_request returns only
-- the new support_requests row's id. The console works in conversations (support_threads), which
-- that id is not. So a visitor who wrote back quoting their reference gave support nothing to look
-- up.
--
-- submit_support_request keeps its signature and its scalar uuid. The iOS app reaches it through
-- the submit-help-message edge function, and shipped builds call whichever version of that
-- function is deployed. A return type cannot change in place anyway (create or replace refuses),
-- so this adds a second function next to it instead.
--
-- It takes the same arguments with the same defaults, so a caller can switch by changing the name,
-- and it files the request by calling submit_support_request itself. Attribution, the address
-- check, the report rules and thread resolution all stay in one place. It is plpgsql, not sql, so
-- the lookup of the request's thread_id runs as a second statement and sees the row the first one
-- inserted. A single SQL statement would read from a snapshot taken before the insert.
--
-- It is security definer because callers cannot read support_requests (there is no select policy),
-- and it is granted exactly as submit_support_request is: authenticated and the service role, which
-- the website's route uses, never anon.

create or replace function public.submit_support_request_with_thread(
  p_category text,
  p_message text,
  p_subject text default null,
  p_email text default null,
  p_name text default null,
  p_source text default 'app',
  p_reported_profile_id uuid default null,
  p_report_surface text default null
)
returns table (request_id uuid, thread_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request uuid;
begin
  v_request := public.submit_support_request(
    p_category, p_message, p_subject, p_email, p_name, p_source, p_reported_profile_id, p_report_surface
  );

  return query
    select r.id, r.thread_id from public.support_requests r where r.id = v_request;
end;
$$;

revoke all on function public.submit_support_request_with_thread(text, text, text, text, text, text, uuid, text)
  from public, anon;
grant execute on function public.submit_support_request_with_thread(text, text, text, text, text, text, uuid, text)
  to authenticated, service_role;
