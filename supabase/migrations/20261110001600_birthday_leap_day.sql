-- Leap-day birthdays get marked on 28 February, instead of not being marked at all.
--
-- 20261110001500 excluded them. Its reasoning was that a leap-day birthday genuinely has no date
-- in a common year and that choosing one picks a side — true as far as it goes, and the wrong
-- call: the effect is that someone born on 29 February is reminded about three years in four,
-- which is a worse answer than picking a side. Between 28 February and 1 March this takes the
-- 28th, keeping the day inside the month the birthday belongs to.
--
-- `Birthday.observed(inYear:)` on the client makes the identical substitution. They have to agree:
-- a push saying the birthday is today while the app shows nothing, or the reverse, is worse than
-- either date on its own.
--
-- A separate migration rather than an edit to 20261110001500, because that one has already run
-- against production. Editing an applied migration leaves the file and the database saying
-- different things, and the difference only surfaces on a fresh `db reset` — somewhere other than
-- where it was introduced.

create or replace function private.birthday_occurrence(p_month smallint, p_day smallint, p_year int)
returns date
language sql
immutable
set search_path = public
as $$
  select make_date(
    p_year,
    p_month,
    case
      when p_month = 2 and p_day = 29
        and not (p_year % 4 = 0 and (p_year % 100 <> 0 or p_year % 400 = 0))
      then 28
      else p_day
    end
  );
$$;

revoke all on function private.birthday_occurrence(smallint, smallint, int) from public, anon, authenticated;

-- Replaced whole rather than patched: the only change is the `dated` CTE, which now resolves each
-- candidate year through the helper instead of excluding leap-day birthdays outright.
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
      -- Rolled forward once this year's has passed, so a December birthday is not reported as 360
      -- days ago every January. Each candidate year is resolved separately, because whether 29
      -- February exists depends on the year being asked about — on 1 December 2026 the next
      -- leap-day birthday falls in 2027, a common year.
      case
        when private.birthday_occurrence(birthday_month, birthday_day, extract(year from subject_local_date)::int) >= subject_local_date
          then private.birthday_occurrence(birthday_month, birthday_day, extract(year from subject_local_date)::int)
        else private.birthday_occurrence(birthday_month, birthday_day, extract(year from subject_local_date)::int + 1)
      end as next_occurrence
    from pairs
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

revoke all on function public.list_birthday_reminder_targets() from public, anon, authenticated;
grant execute on function public.list_birthday_reminder_targets() to service_role;
