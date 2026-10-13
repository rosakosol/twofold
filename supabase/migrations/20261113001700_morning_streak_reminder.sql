-- ============================================================
-- A 10am streak reminder
-- ============================================================
--
-- Two reminders went out for an unanswered daily question: one six hours before the person's day
-- ends ("Keep your streak going") and one an hour before ("1 hour left!"). Both arrive in the
-- evening, which is when a day is already spent. This adds a morning one at 10am, when there is the
-- whole day to answer.
--
-- It is the same reminder in a third position. A person's day ends at their own local midnight
-- (20260912000100), so 10am local is fourteen hours before that boundary, and send-streak-reminders
-- already works by distance from the boundary. It runs as a third mode of that function, with the
-- same rules: only someone who hasn't answered today, only if they have the daily streak reminder
-- switched on (it shares that preference, being the same reminder earlier), and at most once a day,
-- recorded here as kind 'morning'.
--
-- On the two days a year the clocks change, fourteen hours before midnight is 9am or 11am. For a
-- nudge that is fine, and it is not worth a second clock to avoid.

alter table public.streak_reminder_sends
  drop constraint if exists streak_reminder_sends_reminder_kind_check;
alter table public.streak_reminder_sends
  add constraint streak_reminder_sends_reminder_kind_check
  check (reminder_kind in ('morning', 'early', 'final'));

-- The return type grows by a column, so dropped and recreated. Same grants: service_role only.
drop function if exists public.list_streak_reminder_targets();

create function public.list_streak_reminder_targets()
returns table (
  profile_id uuid,
  couple_id uuid,
  partner_id uuid,
  local_date date,
  next_boundary timestamptz,
  current_streak int,
  early_reminder_sent_date date,
  final_reminder_sent_date date,
  morning_reminder_sent_date date
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    c.id,
    case when c.partner_a_id = p.id then c.partner_b_id else c.partner_a_id end,
    private.local_date_at(p.timezone, now()),
    private.next_local_midnight(p.timezone, now()),
    coalesce(ds.current_streak, 0)::int,
    early.sent_for_date,
    final.sent_for_date,
    morning.sent_for_date
  from public.couples c
  join public.profiles p on p.id in (c.partner_a_id, c.partner_b_id)
  left join public.daily_streaks ds on ds.couple_id = c.id
  left join public.streak_reminder_sends early
    on early.profile_id = p.id and early.reminder_kind = 'early'
  left join public.streak_reminder_sends final
    on final.profile_id = p.id and final.reminder_kind = 'final'
  left join public.streak_reminder_sends morning
    on morning.profile_id = p.id and morning.reminder_kind = 'morning'
  where c.status = 'active';
$$;

revoke all on function public.list_streak_reminder_targets() from public, anon, authenticated;
grant execute on function public.list_streak_reminder_targets() to service_role;

create or replace function private.trigger_send_morning_streak_reminders()
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
    raise notice 'send-streak-reminders (morning): project_url/service_role_key not set in Vault yet, skipping this run';
    return;
  end if;

  perform net.http_post(
    url := project_url || '/functions/v1/send-streak-reminders',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || service_key),
    body := '{"morning": true}'::jsonb
  );
end;
$$;

revoke all on function private.trigger_send_morning_streak_reminders() from public, anon, authenticated;

-- Every 15 minutes, like the other two: a person's 10am falls on a quarter hour in every timezone
-- in use, and the function sends to whoever's 10am fell inside the last fifteen minutes.
select cron.schedule('send-morning-streak-reminders', '*/15 * * * *', 'select private.trigger_send_morning_streak_reminders();');
