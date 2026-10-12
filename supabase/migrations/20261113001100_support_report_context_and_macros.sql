-- ============================================================
-- Abuse reports that say who they are about, and saved replies
-- ============================================================
--
-- Two things the support inbox was missing.
--
-- ---------------------------------------------------------------------------
-- Who a report is about
-- ---------------------------------------------------------------------------
--
-- A report from the app names the person it is about: the app attaches their profile id, and
-- submit-help-message puts it in the email. But the inbox does not read the email. It reads the
-- support_requests row, and submit_support_request was only ever handed the message. So a report
-- arrived in the console as the reporter's words with no way to tell who they were about.
--
-- The reported id is now stored on the request, with where the reporter reached them from. No
-- foreign key, for the reason the table gives for profile_id: the record has to outlive the
-- account, and an account that is reported is exactly the one likely to be deleted.
--
-- Only a signed-in caller filing a "Report Abuse" request can set it. The website form has no
-- signed-in reporter, and a field that let anybody attach any profile id to a request would let
-- them make any account look reported.
--
-- admin_report_context is what the console asks when it opens a report: who the person is, how to
-- reach them, and the facts that decide what to do. How often they have been reported and by how
-- many people, whether the reporter has blocked them, and whether the two are partners. Opening it
-- is recorded, like opening an account.
--
-- ---------------------------------------------------------------------------
-- Saved replies
-- ---------------------------------------------------------------------------
--
-- support_macros: a title and a body, inserted into the reply box and edited there before sending.
-- Readable and writable by support admins only. `{{name}}` in a body is filled with the
-- correspondent's first name in the console; nothing here interprets it.

alter table public.support_requests
  add column if not exists reported_profile_id uuid,
  add column if not exists report_surface text;

create index if not exists support_requests_reported_profile_idx
  on public.support_requests (reported_profile_id) where reported_profile_id is not null;

-- Two new optional arguments. Dropped and recreated rather than overloaded: an overload that
-- differs only by trailing defaults makes every existing six-argument call ambiguous.
drop function if exists public.submit_support_request(text, text, text, text, text, text);

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
  end if;

  -- See the header: only a signed-in reporter, only on a report, and never themselves.
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

grant execute on function public.submit_support_request(text, text, text, text, text, text, uuid, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- What the console shows beside a report
-- ---------------------------------------------------------------------------

create or replace function public.admin_report_context(p_request_id uuid)
returns table (
  reported_profile_id uuid,
  report_surface text,
  first_name text,
  email text,
  joined_at timestamptz,
  account_deleted_at timestamptz,
  times_reported integer,
  distinct_reporters integer,
  blocked_by_count integer,
  reporter_blocked_them boolean,
  are_partners boolean,
  were_partners boolean
)
language plpgsql
security definer
set search_path = private, public, auth
as $$
declare
  v_request public.support_requests;
begin
  if not public.is_support_admin() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  select * into v_request from public.support_requests where id = p_request_id;
  if not found or v_request.reported_profile_id is null then
    return;
  end if;

  perform private.record_admin_action(
    'report.view', v_request.reported_profile_id, null, jsonb_build_object('request_id', p_request_id)
  );

  return query
  select
    v_request.reported_profile_id,
    v_request.report_surface,
    p.first_name,
    u.email::text,
    p.created_at,
    p.account_deleted_at,
    (select count(*)::int from public.support_requests r
      where r.reported_profile_id = v_request.reported_profile_id),
    (select count(distinct r.profile_id)::int from public.support_requests r
      where r.reported_profile_id = v_request.reported_profile_id),
    (select count(*)::int from public.blocked_profiles b where b.blocked_id = v_request.reported_profile_id),
    exists (select 1 from public.blocked_profiles b
      where b.blocker_id = v_request.profile_id and b.blocked_id = v_request.reported_profile_id),
    exists (select 1 from public.couples c
      where c.status = 'active'
        and ((c.partner_a_id = v_request.profile_id and c.partner_b_id = v_request.reported_profile_id)
          or (c.partner_b_id = v_request.profile_id and c.partner_a_id = v_request.reported_profile_id))),
    exists (select 1 from public.couples c
      where c.status = 'dissolved'
        and ((c.partner_a_id = v_request.profile_id and c.partner_b_id = v_request.reported_profile_id)
          or (c.partner_b_id = v_request.profile_id and c.partner_a_id = v_request.reported_profile_id)))
  from (select v_request.reported_profile_id as id) target
  left join public.profiles p on p.id = target.id
  left join auth.users u on u.id = target.id;
end;
$$;

revoke all on function public.admin_report_context(uuid) from public, anon;
grant execute on function public.admin_report_context(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Saved replies
-- ---------------------------------------------------------------------------

create table if not exists public.support_macros (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(btrim(title)) between 1 and 80),
  body text not null check (length(btrim(body)) between 1 and 5000),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.support_macros enable row level security;

drop policy if exists "support_macros_support_admins" on public.support_macros;
create policy "support_macros_support_admins" on public.support_macros
  for all to authenticated
  using (public.is_support_admin())
  with check (public.is_support_admin());

revoke all on public.support_macros from anon;
grant select, insert, update, delete on public.support_macros to authenticated;

-- A starting set, in the voice the app already uses. Edit or delete them in the console.
insert into public.support_macros (title, body, created_by) values
  ('Abuse report received',
   'Hi {{name}},

Thanks for telling us, and I''m sorry you''ve had to. We''ve received your report and are looking into it now, and we''ll act on it within 48 hours.

If you haven''t already, you can block them from Settings so they can''t contact you through Twofold. If you ever feel unsafe, please contact your local emergency services (000 in Australia).

Twofold Support', null),
  ('Abuse report: action taken',
   'Hi {{name}},

Following up on your report: we''ve reviewed it and taken action on the account involved. For their privacy we can''t share the details, but they can no longer use Twofold to contact you.

Thank you for letting us know.

Twofold Support', null),
  ('Account deleted',
   'Hi {{name}},

As requested, your Twofold account has been deleted and you won''t be able to sign in to it again. Shared data from your relationship is kept for 90 days in case your partner needs it, then permanently deleted.

If you subscribed through the App Store, please cancel it in Settings > Apple Account > Subscriptions so you aren''t charged again.

Twofold Support', null),
  ('Subscription help',
   'Hi {{name}},

Thanks for getting in touch. If you subscribed in the app, the subscription is managed by Apple: you can view, change or cancel it in Settings > Apple Account > Subscriptions on your iPhone. If you subscribed on our website, reply here and I''ll sort it out for you.

Twofold Support', null),
  ('Bug report: thanks',
   'Hi {{name}},

Thanks for reporting this, and sorry for the trouble. I''ve passed it on and we''ll let you know once it''s fixed. If it happens again, a screenshot or the steps that led to it would help a lot.

Twofold Support', null);
