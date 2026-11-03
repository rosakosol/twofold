-- submit_support_request_with_thread also returns the conversation's reply-to token, so the website's
-- receipt can carry it.
--
-- The receipt asks the visitor to reply, and its Reply-To was plain support@. Inbound mail with no
-- token is matched to a conversation by subject and sender, and a web-form request has no subject,
-- so a reply to the receipt never joined the request's conversation: it started a new one. Replies
-- sent from the console already solve this by addressing Reply-To as `support+t<token>@`, which
-- ingest_support_email resolves to that thread exactly (private.token_from_address). The receipt can
-- do the same once the route has the token, and this is how it gets it.
--
-- The token is what lets mail into a conversation, so the only place the website puts it is the
-- Reply-To of the receipt, which goes to the address the request was filed under. A signed-in caller
-- gets back only the token of a conversation keyed to their own account's address (the email is the
-- account's, not the one posted; see submit_support_request), and a caller with no session always
-- starts a new conversation, so nobody can fish out somebody else's token by calling this.
--
-- A function's result columns cannot change with create or replace, so this drops and re-creates
-- it. Nothing in the database depends on it (it was added in 20261121000200 and only the website's
-- /api/support route calls it), and the drop and the create run in this migration's one
-- transaction, so there is no moment without it. request_id and thread_id keep their names and
-- order: the route deployed before this reads only those two, and keeps working.

drop function public.submit_support_request_with_thread(text, text, text, text, text, text, uuid, text);

create function public.submit_support_request_with_thread(
  p_category text,
  p_message text,
  p_subject text default null,
  p_email text default null,
  p_name text default null,
  p_source text default 'app',
  p_reported_profile_id uuid default null,
  p_report_surface text default null
)
returns table (request_id uuid, thread_id uuid, thread_token text)
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

  -- A second statement, so it sees the row the call above inserted (see 20261121000200).
  return query
    select r.id, r.thread_id, t.token
    from public.support_requests r
    left join public.support_threads t on t.id = r.thread_id
    where r.id = v_request;
end;
$$;

revoke all on function public.submit_support_request_with_thread(text, text, text, text, text, text, uuid, text)
  from public, anon;
grant execute on function public.submit_support_request_with_thread(text, text, text, text, text, text, uuid, text)
  to authenticated, service_role;
