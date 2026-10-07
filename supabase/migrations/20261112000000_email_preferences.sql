-- Email preferences, and the unsubscribe link every non-essential email carries.
--
-- Three things a person can say no to, each one a list:
--
--   product_news      Launches and offers. Opt-in, so false until somebody turns it on: Australia's
--                     Spam Act wants consent for a commercial message, and an account is not that.
--   feedback_updates  "Your idea is on the board" and news about requests you posted. On by
--                     default: it is a reply to something the person did.
--   android_waitlist  Membership of waitlist_signups. Leaving deletes the row, which is the whole
--                     promise the waitlist email makes ("one email when it ships").
--
-- Account, security, billing and support mail is not a list here and cannot be turned off: a
-- password reset someone unsubscribed from is a locked-out account.
--
-- Keyed by email rather than profile, because two of the three lists reach people with no
-- account (the waitlist), and an unsubscribe link has to work for them too.
--
-- The table has no policies. Every read and write goes through the functions below: an email
-- link carries a random token and can change only the row it names, and a signed-in person can
-- change only the row for their own address.

create table public.email_preferences (
  email text primary key check (email = lower(btrim(email)) and email <> ''),
  token uuid not null unique default gen_random_uuid(),
  product_news boolean not null default false,
  feedback_updates boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.email_preferences enable row level security;
revoke all on public.email_preferences from anon, authenticated;

comment on table public.email_preferences is
  'Per-address email lists and the token their unsubscribe links carry. No policies: read and written only through the security-definer functions in 20261112000000.';

-- Feedback-received confirmations already sent, so one request is confirmed once. A table rather
-- than a column on feature_requests, because the author can update their own request and must not
-- be able to clear the stamp and have the email sent again.
create table public.feedback_confirmations (
  feature_id uuid primary key references public.feature_requests (id) on delete cascade,
  sent_at timestamptz not null default now()
);

alter table public.feedback_confirmations enable row level security;
revoke all on public.feedback_confirmations from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Internal: the row for an address, created on first use
-- ---------------------------------------------------------------------------

create or replace function public.email_preferences_token_for(p_email text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(p_email));
  v_token uuid;
begin
  if v_email is null or v_email = '' then
    return null;
  end if;
  insert into public.email_preferences (email) values (v_email)
  on conflict (email) do nothing;
  select token into v_token from public.email_preferences where email = v_email;
  return v_token;
end;
$$;

-- Edge functions (the welcome email) call this with the service role; nobody else needs it.
revoke execute on function public.email_preferences_token_for(text) from public, anon, authenticated;
grant execute on function public.email_preferences_token_for(text) to service_role;

-- ---------------------------------------------------------------------------
-- Joining the Android waitlist
-- ---------------------------------------------------------------------------

-- Replaces the website's direct insert, so it can hand back the token for the confirmation
-- email's "Leave the waitlist" link. 'joined' or 'exists'.
create or replace function public.join_android_waitlist(p_email text)
returns table (status text, token uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(p_email));
begin
  if v_email is null or v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' or length(v_email) > 320 then
    raise exception 'invalid email' using errcode = '22023';
  end if;

  begin
    insert into public.waitlist_signups (email) values (v_email);
    status := 'joined';
  exception when unique_violation then
    status := 'exists';
  end;

  token := public.email_preferences_token_for(v_email);
  return next;
end;
$$;

revoke execute on function public.join_android_waitlist(text) from public;
grant execute on function public.join_android_waitlist(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- From an email link: the token is the credential
-- ---------------------------------------------------------------------------

-- What the unsubscribe page shows. Nothing about the address beyond a masked form of it.
create or replace function public.email_preferences_by_token(p_token uuid)
returns table (masked_email text, product_news boolean, feedback_updates boolean, android_waitlist boolean)
language sql
stable
security definer
set search_path = public
as $$
  select
    left(p.email, 1) || '•••' || substr(p.email, position('@' in p.email)),
    p.product_news,
    p.feedback_updates,
    exists (select 1 from public.waitlist_signups w where w.email = p.email)
  from public.email_preferences p
  where p.token = p_token;
$$;

revoke execute on function public.email_preferences_by_token(uuid) from public;
grant execute on function public.email_preferences_by_token(uuid) to anon, authenticated;

-- One list on or off for the address the token belongs to. False when the token is unknown.
create or replace function public.set_email_preference_by_token(p_token uuid, p_list text, p_enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  select email into v_email from public.email_preferences where token = p_token;
  if v_email is null then
    return false;
  end if;
  perform public.apply_email_preference(v_email, p_list, p_enabled);
  return true;
end;
$$;

revoke execute on function public.set_email_preference_by_token(uuid, text, boolean) from public;
grant execute on function public.set_email_preference_by_token(uuid, text, boolean) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Signed in: the /account page
-- ---------------------------------------------------------------------------

create or replace function public.my_email_preferences()
returns table (email text, product_news boolean, feedback_updates boolean, android_waitlist boolean)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text;
begin
  select lower(u.email) into v_email from auth.users u where u.id = auth.uid();
  if v_email is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  perform public.email_preferences_token_for(v_email);
  return query
    select p.email, p.product_news, p.feedback_updates,
      exists (select 1 from public.waitlist_signups w where w.email = p.email)
    from public.email_preferences p
    where p.email = v_email;
end;
$$;

revoke execute on function public.my_email_preferences() from public, anon;
grant execute on function public.my_email_preferences() to authenticated;

create or replace function public.set_my_email_preference(p_list text, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text;
begin
  select lower(u.email) into v_email from auth.users u where u.id = auth.uid();
  if v_email is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  perform public.email_preferences_token_for(v_email);
  perform public.apply_email_preference(v_email, p_list, p_enabled);
end;
$$;

revoke execute on function public.set_my_email_preference(text, boolean) from public, anon;
grant execute on function public.set_my_email_preference(text, boolean) to authenticated;

-- The one place a list is changed, so the token path and the signed-in path cannot disagree.
-- 'all' turns off everything optional; turning 'all' on is refused, because opting into product
-- news has to be a choice about product news.
create or replace function public.apply_email_preference(p_email text, p_list text, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  case p_list
    when 'product_news' then
      update public.email_preferences set product_news = p_enabled, updated_at = now() where email = p_email;
    when 'feedback_updates' then
      update public.email_preferences set feedback_updates = p_enabled, updated_at = now() where email = p_email;
    when 'android_waitlist' then
      if p_enabled then
        insert into public.waitlist_signups (email) values (p_email) on conflict (email) do nothing;
      else
        delete from public.waitlist_signups where email = p_email;
      end if;
    when 'all' then
      if p_enabled then
        raise exception 'turn lists on one at a time' using errcode = '22023';
      end if;
      update public.email_preferences set product_news = false, feedback_updates = false, updated_at = now()
        where email = p_email;
      delete from public.waitlist_signups where email = p_email;
    else
      raise exception 'unknown list %', p_list using errcode = '22023';
  end case;
end;
$$;

revoke execute on function public.apply_email_preference(text, text, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Feedback received
-- ---------------------------------------------------------------------------

-- Called by the website straight after someone posts a request, as them. Returns what the
-- confirmation email needs, once, and only for the author's own request, posted in the last hour,
-- to an address that has not turned feedback updates off. Anything else returns no row and no
-- email is sent.
create or replace function public.claim_feedback_confirmation(p_feature_id uuid)
returns table (
  email text,
  display_name text,
  title text,
  description text,
  category text,
  slug text,
  token uuid
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text;
  v_request public.feature_requests%rowtype;
begin
  select * into v_request from public.feature_requests r where r.id = p_feature_id;
  if v_request.id is null or v_request.author_id is distinct from auth.uid()
     or v_request.created_at < now() - interval '1 hour' then
    return;
  end if;

  select lower(u.email) into v_email from auth.users u where u.id = auth.uid();
  if v_email is null then
    return;
  end if;
  perform public.email_preferences_token_for(v_email);
  if not (select p.feedback_updates from public.email_preferences p where p.email = v_email) then
    return;
  end if;

  insert into public.feedback_confirmations (feature_id) values (p_feature_id)
  on conflict (feature_id) do nothing;
  if not found then
    return;
  end if;

  return query
    select v_email,
      coalesce(nullif(pr.first_name, ''), 'there'),
      v_request.title,
      v_request.description,
      v_request.category::text,
      v_request.slug,
      p.token
    from public.email_preferences p
    left join public.profiles pr on pr.id = auth.uid()
    where p.email = v_email;
end;
$$;

revoke execute on function public.claim_feedback_confirmation(uuid) from public, anon;
grant execute on function public.claim_feedback_confirmation(uuid) to authenticated;
