-- ---------------------------------------------------------------------------
-- Mail sent straight to support@ becomes a ticket too
-- ---------------------------------------------------------------------------
--
-- `support_requests` captures what goes through the app's Help screen and the website's form.
-- Anything somebody types into their own mail client and sends to support@twofoldapp.com.au is
-- invisible to it — which, now that every published address points there, is most of the mail that
-- will arrive. Zoho Mail can POST incoming messages to a webhook; `ingest-support-email` receives
-- them and calls the function below.
--
-- ---------------------------------------------------------------------------
-- message_id, and why it has to be unique
-- ---------------------------------------------------------------------------
--
-- A webhook that is retried, or a mailbox rule that fires twice, delivers the same message again.
-- RFC 5322 gives every message a globally unique `Message-ID`, so a unique index on it makes a
-- redelivery a no-op rather than a second ticket — the same trick `streak_repair_credits` plays
-- with a store transaction id.
--
-- Nullable, because a form submission has no message id and two of them must not collide on null.
-- Postgres treats nulls as distinct in a unique index, which is exactly the behaviour wanted.

alter table public.support_requests
  add column if not exists message_id text;

create unique index if not exists support_requests_message_id_key
  on public.support_requests (message_id) where message_id is not null;

comment on column public.support_requests.message_id is
  'RFC 5322 Message-ID for a request that arrived as email, so a redelivered webhook is a no-op '
  'rather than a duplicate ticket. Null for the app and website forms, which have none.';

-- `source` gains 'email'. Rewritten rather than altered in place because a check constraint cannot
-- be extended.
alter table public.support_requests drop constraint if exists support_requests_source_check;
alter table public.support_requests
  add constraint support_requests_source_check check (source in ('app', 'web', 'email'));

-- ---------------------------------------------------------------------------
-- Writing one
-- ---------------------------------------------------------------------------
--
-- Separate from `submit_support_request` and granted to `service_role` alone, because the two
-- differ in the one way that matters: that function resolves the sender from `auth.uid()` and
-- refuses to take an address from the caller, precisely so nobody can file a ticket as somebody
-- else. An email has no session, so the address MUST come from the payload — which is only safe
-- because the caller is the edge function holding the service key, having already verified the
-- request came from Zoho.
--
-- Granting this to `authenticated` would hand every signed-in user the ability to forge a ticket
-- from any address, which is the exact hole the other function is shaped to avoid.

create or replace function public.ingest_support_email(
  p_message_id text,
  p_email text,
  p_name text,
  p_subject text,
  p_message text,
  p_received_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_id uuid;
  v_profile uuid;
begin
  if coalesce(trim(p_email), '') = '' then
    raise exception 'an address is required' using errcode = '22023';
  end if;

  -- Matched at write time as a convenience, and the console matches again at read time by address,
  -- so a message that arrives before an account exists still resolves later.
  select u.id into v_profile from auth.users u where lower(u.email) = lower(trim(p_email)) limit 1;

  insert into public.support_requests (
    message_id, profile_id, email, name, category, subject, message, source, created_at
  )
  values (
    nullif(trim(p_message_id), ''),
    v_profile,
    lower(trim(p_email)),
    nullif(trim(p_name), ''),
    -- Email carries no category — the picker is a form control. 'Email' is honest about where it
    -- came from rather than guessing at a topic from the subject line.
    'Email',
    nullif(trim(p_subject), ''),
    left(coalesce(trim(p_message), ''), 20000),
    'email',
    coalesce(p_received_at, now())
  )
  -- A redelivery. Returns nothing and the caller reports success, because the ticket it is trying
  -- to create already exists — treating that as an error would make Zoho retry forever.
  on conflict (message_id) where message_id is not null do nothing
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.ingest_support_email(text, text, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.ingest_support_email(text, text, text, text, text, timestamptz)
  to service_role;
