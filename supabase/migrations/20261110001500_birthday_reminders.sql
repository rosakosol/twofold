-- "Max's birthday is on Saturday", and then "it's today".
--
-- Two questions, with two different answers, which is the whole reason this is not a fixed-hour
-- daily job like the ones before 20260912000100:
--
--   * Which date is the birthday? The *subject's* local date. Melbourne and London are eleven
--     hours apart, so reading the date where the recipient stands tells somebody in London it is
--     their partner's birthday only once London turns over, by which point Melbourne is most of a
--     day in — and the other way round it fires most of a day early. `Person.isBirthdayToday` on
--     the client makes the same choice, so the push and the celebration screen agree.
--
--   * When should it arrive? The *recipient's* local morning. Nobody wants this at 3am, and the
--     recipient is the one holding the phone.
--
-- Everything needed for that already exists: `private.local_date_at` and `private.safe_timezone`
-- (20260908000000) handle IANA zones and DST, `profiles.timezone` is rewritten on every foreground
-- by `updateDeviceContext`, and `streak_reminder_sends` (20260912000100) is the ledger shape this
-- copies. The older crons' "no per-user timezone-aware scheduling infra yet" stopped being true
-- then.

-- The mute switch, per recipient. Distinct from `partner_birthday_wish` (20261110001400), which is
-- the message a partner actually types on the day — one is the app reminding you, the other is a
-- person talking to you, and somebody may well want the second without the first.
alter table public.notification_preferences
  add column if not exists partner_birthday_reminder boolean not null default true;

comment on column public.notification_preferences.partner_birthday_reminder is
  'Whether to send this person the "your partner''s birthday is coming up" reminders — three days '
  'before and on the morning. Not the same switch as partner_birthday_wish.';

grant update (partner_birthday_reminder) on public.notification_preferences to authenticated;

-- One row per recipient per kind, holding the birthday year it last fired for.
--
-- The ledger is not optional here, because the job runs hourly rather than daily: it has to, to
-- catch each recipient's own local morning. Without this, anyone whose timezone shifts — travel,
-- or a DST transition that repeats an hour — can match the morning window twice and be told twice.
-- Keyed on the year rather than a bare timestamp so the answer to "already sent?" is exact, and so
-- it rearms by itself next year.
create table if not exists public.birthday_reminder_sends (
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  reminder_kind text not null check (reminder_kind in ('upcoming', 'today')),
  sent_for_year int not null,
  updated_at timestamptz not null default now(),
  primary key (recipient_id, reminder_kind)
);

-- No policies, same as `streak_reminder_sends`: only the edge function touches this and it holds
-- the service role, which bypasses RLS. Enabling RLS with no policy is what keeps app users out.
alter table public.birthday_reminder_sends enable row level security;

-- Who should hear about a birthday right now.
--
-- Returns the recipient (the partner of whoever's birthday it is), never the birthday person
-- themselves — the app already marks your own day on screen and a push telling you when you were
-- born would be strange.
create or replace function public.list_birthday_reminder_targets()
returns table (
  recipient_id uuid,
  subject_id uuid,
  subject_name text,
  subject_birthday_month smallint,
  subject_birthday_day smallint,
  recipient_local_hour int,
  days_until int,
  upcoming_sent_for_year int,
  today_sent_for_year int,
  birthday_year int
)
language sql
stable
security definer
set search_path = public
as $$
  with pairs as (
    select
      recipient.id as recipient_id,
      subject.id as subject_id,
      subject.first_name as subject_name,
      subject.birthday_month,
      subject.birthday_day,
      -- The recipient's clock decides when this lands.
      extract(hour from (now() at time zone private.safe_timezone(recipient.timezone)))::int as recipient_local_hour,
      -- The subject's clock decides what "today" means for their birthday.
      private.local_date_at(subject.timezone, now()) as subject_local_date
    from public.couples c
    join public.profiles recipient on recipient.id in (c.partner_a_id, c.partner_b_id)
    join public.profiles subject
      on subject.id = case when c.partner_a_id = recipient.id then c.partner_b_id else c.partner_a_id end
    where c.status = 'active'
      and subject.birthday_month is not null
      and subject.birthday_day is not null
  ),
  dated as (
    select
      pairs.*,
      -- This year's occurrence in the subject's own calendar, rolled forward once it has passed so
      -- December birthdays are not reported as being 360 days ago every January.
      case
        when make_date(extract(year from subject_local_date)::int, birthday_month, birthday_day) >= subject_local_date
          then make_date(extract(year from subject_local_date)::int, birthday_month, birthday_day)
        else make_date(extract(year from subject_local_date)::int + 1, birthday_month, birthday_day)
      end as next_occurrence
    from pairs
    -- 29 February in a non-leap year has no `make_date`, and asking for one raises rather than
    -- returning null. Excluded here rather than coalesced: a leap-day birthday genuinely has no
    -- date this year, and inventing the 28th or the 1st picks a side that is not ours to pick.
    where not (birthday_month = 2 and birthday_day = 29
               and not (extract(year from subject_local_date)::int % 4 = 0
                        and (extract(year from subject_local_date)::int % 100 <> 0
                             or extract(year from subject_local_date)::int % 400 = 0)))
  )
  select
    dated.recipient_id,
    dated.subject_id,
    dated.subject_name,
    dated.birthday_month,
    dated.birthday_day,
    dated.recipient_local_hour,
    (dated.next_occurrence - dated.subject_local_date)::int as days_until,
    upcoming.sent_for_year,
    today.sent_for_year,
    extract(year from dated.next_occurrence)::int as birthday_year
  from dated
  left join public.birthday_reminder_sends upcoming
    on upcoming.recipient_id = dated.recipient_id and upcoming.reminder_kind = 'upcoming'
  left join public.birthday_reminder_sends today
    on today.recipient_id = dated.recipient_id and today.reminder_kind = 'today'
  where (dated.next_occurrence - dated.subject_local_date)::int in (0, 3);
$$;

-- Service role only: this enumerates every couple in the app, so no app user may call it. Same
-- reasoning as `list_streak_reminder_targets`.
revoke all on function public.list_birthday_reminder_targets() from public, anon, authenticated;
grant execute on function public.list_birthday_reminder_targets() to service_role;

create or replace function private.trigger_send_birthday_reminders()
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
    raise notice 'send-birthday-reminders: project_url/service_role_key not set in Vault yet, skipping this run';
    return;
  end if;

  perform net.http_post(
    url := project_url || '/functions/v1/send-birthday-reminders',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_key),
    body := '{}'::jsonb
  );
end;
$$;

revoke all on function private.trigger_send_birthday_reminders() from public, anon, authenticated;

-- Hourly, on the hour. Not daily: the whole point is to catch each recipient's own local morning,
-- and those are spread across every hour of the day. The function picks the one hour that is
-- morning for each person, and the ledger stops a repeated hour sending twice.
select cron.schedule('send-birthday-reminders', '0 * * * *', 'select private.trigger_send_birthday_reminders();');
