-- ---------------------------------------------------------------------------
-- Welcome email
-- ---------------------------------------------------------------------------
--
-- Email confirmation stays off, for the reasons SaveAccountView and
-- `signUpWithPassword` both depend on: `signUp` returning a session is what lets an
-- entire onboarding's worth of state flush in one shot, what lets an invite code be
-- generated, and what lets a web purchase follow a sign-up. Turning confirmations on
-- breaks all three.
--
-- The cost of that is the one failure it would have caught: a mistyped address makes an
-- unrecoverable account. Someone signs up as jhon@gmial.com, pairs, accumulates a year of
-- memories and a subscription, then changes phone — and password recovery goes to an
-- address they do not own. There is no way back, for an app whose whole value is the
-- history behind that credential.
--
-- A welcome email does not fix that, but it tells the one person who can: whoever really
-- owns the address that was typed. It gates nothing and blocks nobody.
--
-- WHY A COLUMN AND NOT DAY-BUCKETING
--
-- send-partner-invite-reminders avoids persisting "already sent" state by bucketing on UTC
-- calendar day, which works because a nudge landing a day late is still a nudge. A welcome
-- email is once-only and wants to be prompt, and those two together are exactly what
-- bucketing cannot give: a short window risks double-sends across overlapping runs, and a
-- day-wide one delays it by up to a day. So this is stamped.

alter table public.profiles
  add column if not exists welcome_email_sent_at timestamptz;

comment on column public.profiles.welcome_email_sent_at is
  'When the welcome email went out. Null means not yet sent; send-welcome-emails claims a row '
  'by stamping it. Server-written only — see private.reject_client_welcome_writes.';

-- ---------------------------------------------------------------------------
-- Clients may not touch it
-- ---------------------------------------------------------------------------
--
-- Not for tidiness. The cron sends to whoever is not yet stamped, so a client able to write
-- null back is a client able to make us re-send the welcome email on demand — to an address
-- it chose at sign-up and may not own. That is a spam cannon pointed at a stranger, aimed
-- from an ordinary account.
--
-- Same shape and same reasoning as private.reject_client_subscription_writes
-- (20260915000000): `current_user` rather than a column grant, because revoking UPDATE on a
-- single column left has_column_privilege still answering true there; and `is distinct from`
-- rather than `<>`, because the column is null on a fresh profile and `null <> x` is null,
-- which is not true and would let the write through.
create or replace function private.reject_client_welcome_writes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.welcome_email_sent_at is not null then
      raise exception 'welcome_email_sent_at is set by send-welcome-emails, not by the client'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if new.welcome_email_sent_at is distinct from old.welcome_email_sent_at then
    raise exception 'welcome_email_sent_at is set by send-welcome-emails, not by the client'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_reject_client_welcome_writes on public.profiles;
create trigger trg_reject_client_welcome_writes
  before insert or update on public.profiles
  for each row execute function private.reject_client_welcome_writes();

-- ---------------------------------------------------------------------------
-- The cron
-- ---------------------------------------------------------------------------
--
-- Same pg_cron + pg_net + Vault pattern as 20260717020000, and no new secrets.
--
-- Every fifteen minutes rather than daily: this one is time-sensitive in a way the reminder
-- jobs are not. If the address was mistyped, the sooner its real owner hears about it the
-- likelier the account is still empty enough to be worth telling us about.
create or replace function private.trigger_send_welcome_emails()
returns void
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare
  project_url text;
  service_key text;
begin
  select decrypted_secret into project_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into service_key from vault.decrypted_secrets where name = 'service_role_key';

  if project_url is null or service_key is null then
    raise notice 'send-welcome-emails: project_url/service_role_key not set in Vault yet, skipping this run';
    return;
  end if;

  perform net.http_post(
    url := project_url || '/functions/v1/send-welcome-emails',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_key),
    body := '{}'::jsonb
  );
end;
$$;

select cron.unschedule('send-welcome-emails') where exists (
  select 1 from cron.job where jobname = 'send-welcome-emails'
);
select cron.schedule('send-welcome-emails', '*/15 * * * *', 'select private.trigger_send_welcome_emails();');

-- ---------------------------------------------------------------------------
-- Everyone who already exists is treated as already welcomed
-- ---------------------------------------------------------------------------
--
-- Without this the first run would find every profile ever created unstamped and mail the
-- entire user base a welcome. The function also refuses anything older than its own window,
-- so this is the belt to that braces — but it is the half that cannot be got wrong by
-- editing a constant later.
--
-- `now()` rather than each profile's created_at: the stamp means "we are not going to send
-- one", and dating that to a sign-up we never emailed about would be a record of something
-- that did not happen.
update public.profiles set welcome_email_sent_at = now() where welcome_email_sent_at is null;
