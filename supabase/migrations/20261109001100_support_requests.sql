-- ---------------------------------------------------------------------------
-- Support requests, as rows
-- ---------------------------------------------------------------------------
--
-- Both contact paths — the app's Help screen via `submit-help-message`, and the website's form via
-- `/api/support` — compose an email, send it to support@twofoldapp.com.au, and keep nothing. So
-- the 48-hour response the app promises for an abuse report rests entirely on somebody reading
-- that inbox, there is no way to tell whether a request was answered, and the support console's
-- moderation page has to say in as many words that it cannot show a queue.
--
-- This is the queue. The email keeps being sent exactly as it is today — it is the thing that
-- actually notifies anyone, and nothing here is allowed to jeopardise it.
--
-- ---------------------------------------------------------------------------
-- Storing this content is a different question from storing their memories
-- ---------------------------------------------------------------------------
--
-- The rule for the support console has been status and structure, never content: no memories, no
-- photos, no answers, flights counted rather than listed. A support message is content, and it is
-- stored here anyway, because the distinction that rule is drawing is not "text" versus "not text"
-- — it is between what somebody wrote for themselves and their partner, and what they deliberately
-- wrote TO us in order to be helped. Reading the second is the whole point of them sending it.
--
-- The privacy policy already covers it both ways: "Anything you send us in a support request"
-- appears under what stays private from a partner, and "anything you email us is held in Australia
-- too" — which this still is, since the database is in the Sydney region. Nothing about where the
-- content lives changes.
--
-- ---------------------------------------------------------------------------
-- Attribution is resolved here, never taken from the request
-- ---------------------------------------------------------------------------
--
-- `submit_support_request` is callable by `anon`, because the website's form serves visitors who
-- cannot sign in — often precisely because signing in is what they are writing about. That makes
-- a `profile_id` parameter unacceptable: anyone could file a ticket against anybody.
--
-- So there is no such parameter. A signed-in caller's profile and email come from `auth.uid()` and
-- `auth.users`; an anonymous one supplies an email and gets a null profile. The console matches
-- the two up by address at read time and says which it is.
--
-- The anon grant is worth being explicit about: it is exactly as reachable as the email endpoint it
-- accompanies, and somebody bypassing the website's form to call this directly gets a row and no
-- email — strictly less harm than today, where the same bypass gets mail out of our own sending
-- domain. A junk row is cheaper than a junk send.

create table if not exists public.support_requests (
  id uuid primary key default gen_random_uuid(),

  -- Null for a website submission. No foreign key, deliberately, and for the reason that keeps
  -- recurring here: the record has to outlive the account. Half of what arrives is "please delete
  -- my account", and a cascade would erase the request at the moment it was granted.
  profile_id uuid,

  -- The account's own address for a signed-in sender, resolved server-side; the supplied one
  -- otherwise. Never client-supplied for a signed-in caller — that is the field a reply goes to.
  email text,
  name text,

  category text not null,
  subject text,
  message text not null,

  source text not null check (source in ('app', 'web')),

  -- Deliberately two states and not a workflow. A support queue for one person needs to answer
  -- "is this dealt with", and every additional state is one more thing to keep accurate by hand.
  status text not null default 'open' check (status in ('open', 'closed')),
  handled_by uuid,
  handled_at timestamptz,
  handler_note text,

  created_at timestamptz not null default now()
);

comment on table public.support_requests is
  'Contact-form submissions from the app and website, kept so there is a queue rather than only an '
  'inbox. The email is still sent; this does not replace it. Unreadable over PostgREST — RLS is on '
  'with no select policy, and the console reads it through is_support_admin()-gated functions.';

create index if not exists support_requests_open_idx
  on public.support_requests (created_at desc) where status = 'open';

create index if not exists support_requests_email_idx
  on public.support_requests (lower(email));

alter table public.support_requests enable row level security;

-- RLS on with NO policies at all, which denies everything to anon and authenticated including the
-- sender. That is deliberate rather than an omission: reads go through the gated functions below,
-- and writes go through `submit_support_request`, which is security definer. A sender re-reading
-- their own ticket is not a feature anything asks for, and a select policy would be one more thing
-- that has to stay right.
revoke all on public.support_requests from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Writing one
-- ---------------------------------------------------------------------------

create or replace function public.submit_support_request(
  p_category text,
  p_message text,
  p_subject text default null,
  p_email text default null,
  p_name text default null,
  p_source text default 'app'
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_id uuid;
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
  end if;

  insert into public.support_requests (profile_id, email, name, category, subject, message, source)
  values (
    v_uid,
    v_email,
    nullif(trim(p_name), ''),
    trim(p_category),
    nullif(trim(p_subject), ''),
    -- Capped at the same length both callers already enforce, so a direct call cannot store more
    -- than the forms allow.
    left(trim(p_message), 5000)
  , p_source)
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.submit_support_request(text, text, text, text, text, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Reading the queue
-- ---------------------------------------------------------------------------
--
-- `matched_profile_id` is how a website submission from somebody who could not sign in still
-- reaches their account: the address they typed is looked up at read time rather than stored as a
-- link, so a ticket filed before an account existed still resolves once it does.

create or replace function public.admin_support_requests(
  p_status text default 'open',
  p_limit integer default 100
)
returns table (
  id uuid,
  profile_id uuid,
  matched_profile_id uuid,
  email text,
  name text,
  category text,
  subject text,
  message text,
  source text,
  status text,
  handler_note text,
  handled_at timestamptz,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  return query
    select
      r.id, r.profile_id,
      coalesce(r.profile_id, (select u.id from auth.users u where lower(u.email) = lower(r.email) limit 1)),
      r.email, r.name, r.category, r.subject, r.message, r.source, r.status,
      r.handler_note, r.handled_at, r.created_at
    from public.support_requests r
    where p_status is null or r.status = p_status
    order by r.created_at desc
    limit least(greatest(coalesce(p_limit, 100), 1), 500);
end;
$$;

create or replace function public.admin_set_support_request_status(
  p_id uuid,
  p_status text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = private, public
as $$
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  if p_status not in ('open', 'closed') then
    raise exception 'unknown status' using errcode = '22023';
  end if;

  update public.support_requests
  set status = p_status,
      handled_by = case when p_status = 'closed' then auth.uid() else null end,
      handled_at = case when p_status = 'closed' then now() else null end,
      handler_note = nullif(trim(p_note), '')
  where id = p_id;

  if not found then
    raise exception 'no such request';
  end if;

  -- Recorded against the SENDER, not the request, so that closing a ticket shows up in the same
  -- history as everything else done to that account. A null profile_id (a website submission from
  -- somebody with no account) simply has no subject, which the log tolerates.
  perform private.record_admin_action(
    'support.' || p_status,
    (select profile_id from public.support_requests where id = p_id),
    p_note,
    jsonb_build_object('request_id', p_id)
  );
end;
$$;

revoke execute on function public.admin_support_requests(text, integer) from anon;
revoke execute on function public.admin_set_support_request_status(uuid, text, text) from anon;
grant execute on function public.admin_support_requests(text, integer) to authenticated;
grant execute on function public.admin_set_support_request_status(uuid, text, text) to authenticated;
