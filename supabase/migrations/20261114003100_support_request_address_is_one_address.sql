-- An anonymous support request's address has to be one plain address.
--
-- `submit_support_request` is anon-callable on purpose (the website form has no session), and for
-- that caller the address is whatever was posted -- `nullif(trim(p_email), '')`, nothing more. The
-- website route checks the format first, but the RPC is reachable directly with the publishable key,
-- and then nothing checks it at all.
--
-- That address becomes `support_threads.email`, and `send-support-reply` hands it to denomailer as
-- `to`. denomailer splits `Name <addr>` itself, validates only the part inside the brackets, and
-- writes the name into the DATA stream as `To: <name> <addr>` with no escaping. So a posted address
-- of `x\r\n\r\n<anything>\r\n.\r\n<SMTP commands> <someone@example.com>` passes its check and, the
-- moment an admin answers the thread, injects headers, a body, or (through the lone ".") commands
-- on a session authenticated as support@. The same class of hole dotStuff closed for bodies.
--
-- Refused here, where the value enters, rather than only where it is used: a stored address that
-- cannot be replied to is a ticket nobody can answer. `send-support-reply` refuses a malformed
-- recipient as well, for rows written before this.
--
-- Signed-in callers are unaffected: their address is read from auth.users, never from the request.
--
-- Body identical to 20261113001100 apart from the check.

create or replace function public.submit_support_request(
  p_category text,
  p_message text,
  p_subject text default null,
  p_email text default null,
  p_name text default null,
  p_source text default 'app',
  p_reported_profile_id uuid default null,
  p_report_surface text default null
)
returns uuid
language plpgsql
security definer
set search_path = private, public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_id uuid;
  v_thread uuid;
  v_reported uuid;
begin
  if coalesce(trim(p_message), '') = '' then
    raise exception 'a message is required' using errcode = '22023';
  end if;
  if coalesce(trim(p_category), '') = '' then
    raise exception 'a category is required' using errcode = '22023';
  end if;
  if p_source not in ('app', 'web') then
    raise exception 'unknown source' using errcode = '22023';
  end if;

  -- A signed-in sender's address is their account's, not whatever was posted. This is the field a
  -- reply is sent to, and letting a caller choose it would make this an open relay for support
  -- replies.
  if v_uid is not null then
    select u.email into v_email from auth.users u where u.id = v_uid;
  else
    v_email := nullif(trim(p_email), '');
    -- One bare address: no display name, no list, nothing that can end a header line. Stricter
    -- than the website's own check only in the characters a real address does not contain.
    if v_email is null
       or length(v_email) > 320
       or v_email !~ '^[^[:space:][:cntrl:]<>,;"@]+@[^[:space:][:cntrl:]<>,;"@]+\.[^[:space:][:cntrl:]<>,;"@]+$' then
      raise exception 'a single valid email address is required' using errcode = '22023';
    end if;
  end if;

  -- See 20261113001100: only a signed-in reporter, only on a report, and never themselves.
  if v_uid is not null and trim(p_category) = 'Report Abuse' and p_reported_profile_id is distinct from v_uid then
    v_reported := p_reported_profile_id;
  end if;

  -- No recipient address: a form submission has no token to carry, so this always resolves by the
  -- derived key or starts a conversation.
  v_thread := private.resolve_support_thread(null, p_subject, v_email, v_uid, now());

  insert into public.support_requests (
    thread_id, profile_id, email, name, category, subject, message, source, thread_key,
    reported_profile_id, report_surface
  )
  values (
    v_thread, v_uid, v_email, nullif(trim(p_name), ''), trim(p_category),
    nullif(trim(p_subject), ''), left(trim(p_message), 5000), p_source,
    private.support_thread_key(p_subject, v_email),
    v_reported, case when v_reported is not null then left(nullif(trim(p_report_surface), ''), 100) end
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- `create or replace` keeps the existing grants; restated so this file says what it leaves open.
grant execute on function public.submit_support_request(text, text, text, text, text, text, uuid, text)
  to anon, authenticated;
