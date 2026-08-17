-- Moves the daily-question/streak day boundary off "whenever this couple happened to pair"
-- (20260829000500 anchored it to couples.created_at, 20260901001700 extended the same idea to
-- profiles.created_at for solo users) and onto real local midnight.
--
-- The old anchor is why a couple who connected at 21:45 had their streak roll over at 21:45 every
-- day - a time with no meaning to anyone. Local midnight is what people actually expect "today"
-- to mean.
--
-- WHOSE midnight, for a couple spanning two timezones: the *later* of the two. Concretely the
-- shared day is `greatest(local_date_a, local_date_b)` and it rolls at
-- `greatest(next_midnight_a, next_midnight_b)` - those two are consistent (the max local date
-- advances exactly when the partner who is ahead passes their own midnight). Picking the later
-- one means the day can never end before either partner's own midnight, so nobody is cut off
-- while it's still today where they are. For same/near-timezone couples - the common case - it
-- collapses to simply "their local midnight", which is the whole point of this change.
--
-- Day identity also switches from an integer day-index to a real `date`. The index only ever
-- existed to express "days since the anchor"; with calendar days there's an honest calendar date
-- to store, and consecutive-day checks become `= previous + 1` instead of index arithmetic that
-- silently depended on the anchor.

-- ---------------------------------------------------------------------------
-- Timezone, reported by the device (see BackendService.updateTimezone).
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists timezone text;

-- Never trusts the stored string blindly: an unknown/renamed IANA name (or a client writing junk)
-- would make every `at time zone` call below throw, taking down the daily question and streak
-- entirely. Falls back to UTC instead - wrong-but-harmless, and self-heals the moment the client
-- reports a good value.
create or replace function private.safe_timezone(p_tz text)
returns text
language sql
stable
set search_path = public
as $$
  select coalesce((select name from pg_timezone_names where name = p_tz limit 1), 'UTC');
$$;

create or replace function private.local_date_at(p_tz text, p_at timestamptz)
returns date
language sql
stable
set search_path = public
as $$
  select (p_at at time zone private.safe_timezone(p_tz))::date;
$$;

-- The next local midnight strictly after `p_at`, as an absolute instant.
create or replace function private.next_local_midnight(p_tz text, p_at timestamptz)
returns timestamptz
language sql
stable
set search_path = public
as $$
  select (((p_at at time zone private.safe_timezone(p_tz))::date + 1)::timestamp
          at time zone private.safe_timezone(p_tz));
$$;

-- A couple's shared day - the *later* of the two partners' midnights (see header).
create or replace function private.couple_day(p_couple_id uuid, p_at timestamptz default now())
returns table (local_date date, next_boundary timestamptz)
language sql
stable
set search_path = public
as $$
  select
    greatest(private.local_date_at(pa.timezone, p_at), private.local_date_at(pb.timezone, p_at)),
    greatest(private.next_local_midnight(pa.timezone, p_at), private.next_local_midnight(pb.timezone, p_at))
  from public.couples c
  join public.profiles pa on pa.id = c.partner_a_id
  join public.profiles pb on pb.id = c.partner_b_id
  where c.id = p_couple_id;
$$;

-- "Today" for whoever is calling: their couple's shared day if they're paired, otherwise their
-- own local day. Solo (unpaired) users answer the daily question too - 20260901001700 added that
-- path and it must keep working.
create or replace function private.viewer_day(p_at timestamptz default now())
returns table (couple_id uuid, local_date date, next_boundary timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  with mine as (
    select id, partner_a_id, partner_b_id
    from public.couples
    where (partner_a_id = auth.uid() or partner_b_id = auth.uid()) and status = 'active'
    limit 1
  )
  select m.id,
         greatest(private.local_date_at(pa.timezone, p_at), private.local_date_at(pb.timezone, p_at)),
         greatest(private.next_local_midnight(pa.timezone, p_at), private.next_local_midnight(pb.timezone, p_at))
  from mine m
  join public.profiles pa on pa.id = m.partner_a_id
  join public.profiles pb on pb.id = m.partner_b_id
  union all
  select null::uuid,
         private.local_date_at(p.timezone, p_at),
         private.next_local_midnight(p.timezone, p_at)
  from public.profiles p
  where p.id = auth.uid() and not exists (select 1 from mine)
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- Day identity: int index -> real date.
-- ---------------------------------------------------------------------------
alter table public.game_sessions add column if not exists daily_local_date date;
create index if not exists game_sessions_daily_date_idx
  on public.game_sessions (couple_id, daily_local_date) where is_daily;
create index if not exists game_sessions_daily_solo_date_idx
  on public.game_sessions (initiator_id, daily_local_date) where is_daily and couple_id is null;

-- Stamped explicitly at creation from now on. Backfilled best-effort from the old anchor math so
-- an in-flight daily question isn't orphaned (and immediately re-created as a duplicate) the
-- moment this lands. Couple sessions anchor on couples.created_at, solo ones on the initiator's
-- profile - matching whichever anchor actually produced them.
update public.game_sessions gs
set daily_local_date = (c.created_at + ((floor(extract(epoch from (gs.created_at - c.created_at)) / 86400)::int) || ' days')::interval)::date
from public.couples c
where c.id = gs.couple_id and gs.is_daily and gs.daily_local_date is null;

update public.game_sessions gs
set daily_local_date = (p.created_at + ((floor(extract(epoch from (gs.created_at - p.created_at)) / 86400)::int) || ' days')::interval)::date
from public.profiles p
where p.id = gs.initiator_id and gs.couple_id is null and gs.is_daily and gs.daily_local_date is null;

alter table public.daily_streaks add column if not exists last_answered_date date;

update public.daily_streaks ds
set last_answered_date = (c.created_at + (ds.last_answered_day_index || ' days')::interval)::date
from public.couples c
where c.id = ds.couple_id and ds.last_answered_day_index is not null and ds.last_answered_date is null;

alter table public.daily_streaks drop column if exists last_answered_day_index;

-- The reminder dedup columns were day-indexes against the old anchor too. Same switch; stale
-- values are dropped rather than converted (worst case one couple gets one duplicate nudge on the
-- changeover day, strictly better than carrying a wrong index forward and suppressing a real one).
alter table public.daily_streaks add column if not exists final_reminder_sent_date date;
alter table public.daily_streaks add column if not exists early_reminder_sent_date date;
alter table public.daily_streaks drop column if exists final_reminder_sent_day_index;
alter table public.daily_streaks drop column if exists early_reminder_sent_day_index;

-- ---------------------------------------------------------------------------
-- advance_game_session: keeps the both-partners gate restored in 20260907000000, now keyed on the
-- couple's local date instead of the anchor-relative day index.
-- ---------------------------------------------------------------------------
create or replace function public.advance_game_session()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_rounds int;
  v_couple_id uuid;
  v_initiator_id uuid;
  v_partner_a_id uuid;
  v_partner_b_id uuid;
  v_partner_a_count int;
  v_partner_b_count int;
  v_solo_count int;
  v_both_complete boolean;
  v_is_daily boolean;
  v_local_date date;
begin
  select total_rounds, couple_id, is_daily, initiator_id
  into v_total_rounds, v_couple_id, v_is_daily, v_initiator_id
  from public.game_sessions where id = new.session_id;

  if v_couple_id is null then
    select count(distinct round_number) into v_solo_count
    from public.game_responses
    where session_id = new.session_id and responder_id = v_initiator_id;

    v_both_complete := v_solo_count >= v_total_rounds;

    update public.game_sessions
    set started_at = coalesce(started_at, now()),
        updated_at = now(),
        status = (case when v_both_complete then 'completed' else 'active' end)::public.game_status,
        completed_at = case when v_both_complete then coalesce(completed_at, now()) else completed_at end
    where id = new.session_id;

    return new;
  end if;

  select partner_a_id, partner_b_id into v_partner_a_id, v_partner_b_id
  from public.couples where id = v_couple_id;

  select count(distinct round_number) into v_partner_a_count
  from public.game_responses
  where session_id = new.session_id and responder_id = v_partner_a_id;

  select count(distinct round_number) into v_partner_b_count
  from public.game_responses
  where session_id = new.session_id and responder_id = v_partner_b_id;

  v_both_complete := v_partner_a_count >= v_total_rounds and v_partner_b_count >= v_total_rounds;

  update public.game_sessions
  set started_at = coalesce(started_at, now()),
      updated_at = now(),
      status = (case when v_both_complete then 'completed' else 'active' end)::public.game_status,
      completed_at = case when v_both_complete then coalesce(completed_at, now()) else completed_at end
  where id = new.session_id;

  if v_is_daily and v_both_complete then
    select local_date into v_local_date from private.couple_day(v_couple_id);

    insert into public.daily_streaks (couple_id, current_streak, longest_streak, last_answered_date, updated_at)
    values (v_couple_id, 1, 1, v_local_date, now())
    on conflict (couple_id) do update set
      current_streak = case
        when public.daily_streaks.last_answered_date = v_local_date then public.daily_streaks.current_streak
        when public.daily_streaks.last_answered_date = v_local_date - 1 then public.daily_streaks.current_streak + 1
        else 1
      end,
      longest_streak = greatest(
        public.daily_streaks.longest_streak,
        case
          when public.daily_streaks.last_answered_date = v_local_date then public.daily_streaks.current_streak
          when public.daily_streaks.last_answered_date = v_local_date - 1 then public.daily_streaks.current_streak + 1
          else 1
        end
      ),
      last_answered_date = v_local_date,
      updated_at = now();
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Reads. All now agree on one definition of "today" (private.viewer_day / private.couple_day).
-- Structure below is otherwise unchanged from 20260901001700 - including its solo branches.
-- ---------------------------------------------------------------------------
create or replace function public.get_daily_question_session()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple_id uuid;
  v_local_date date;
  v_session_id uuid;
  v_content_id uuid;
  v_effective_tier text;
  v_tiers text[];
begin
  select couple_id, local_date into v_couple_id, v_local_date from private.viewer_day();

  if v_local_date is null then
    raise exception 'No profile for the current user';
  end if;

  select id into v_session_id
  from public.game_sessions
  where game_type = 'deep_conversations' and is_daily and status != 'abandoned'
    and daily_local_date = v_local_date
    and (
      (v_couple_id is not null and couple_id = v_couple_id)
      or (v_couple_id is null and couple_id is null and initiator_id = auth.uid())
    )
  limit 1;

  if v_session_id is not null then
    return v_session_id;
  end if;

  v_effective_tier := case
    when v_couple_id is not null then private.couple_effective_tier(v_couple_id)
    else coalesce((select subscription_tier from public.profiles where id = auth.uid()), 'plus')
  end;
  v_tiers := case when v_effective_tier = 'premium' then array['plus', 'premium'] else array['plus'] end;

  select id into v_content_id
  from public.deep_conversation_topics
  where active and tier = any(v_tiers)
    and id not in (
      select gsr.content_id from public.game_session_rounds gsr
      join public.game_sessions gs on gs.id = gsr.session_id
      where gs.game_type = 'deep_conversations'
        and (
          (v_couple_id is not null and gs.couple_id = v_couple_id)
          or (v_couple_id is null and gs.couple_id is null and gs.initiator_id = auth.uid())
        )
    )
  order by random() limit 1;

  if v_content_id is null then
    select id into v_content_id
    from public.deep_conversation_topics where active and tier = any(v_tiers)
    order by random() limit 1;
  end if;

  if v_content_id is null then
    raise exception 'No active discussion content available';
  end if;

  insert into public.game_sessions (couple_id, game_type, initiator_id, status, total_rounds, is_daily, daily_local_date)
  values (v_couple_id, 'deep_conversations', auth.uid(), 'active', 1, true, v_local_date)
  returning id into v_session_id;

  insert into public.game_session_rounds (session_id, round_number, content_id)
  values (v_session_id, 1, v_content_id);

  return v_session_id;
end;
$$;

revoke all on function public.get_daily_question_session() from public;
grant execute on function public.get_daily_question_session() to authenticated;

create or replace function public.get_daily_question_status()
returns table (
  session_id uuid,
  my_answered boolean,
  partner_answered boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select
    gs.id as session_id,
    coalesce(bool_or(gr.responder_id = auth.uid()), false) as my_answered,
    coalesce(bool_or(gr.responder_id <> auth.uid()), false) as partner_answered
  from public.game_sessions gs
  join public.couples c on c.id = gs.couple_id
  left join public.game_responses gr on gr.session_id = gs.id
  where gs.is_daily
    and public.is_couple_member(gs.couple_id)
    and gs.daily_local_date = (select local_date from private.couple_day(c.id))
  group by gs.id;
$$;

revoke all on function public.get_daily_question_status() from public;
grant execute on function public.get_daily_question_status() to authenticated;

-- Lapse rule from 20260907000000, restated against dates.
create or replace function public.get_daily_streak()
returns table (current_streak int, longest_streak int)
language sql
security definer
stable
set search_path = public
as $$
  select
    (case
      when ds.last_answered_date is null then 0
      when ds.last_answered_date >= (select local_date from private.couple_day(c.id)) - 1
        then ds.current_streak
      else 0
    end)::int as current_streak,
    ds.longest_streak
  from public.daily_streaks ds
  join public.couples c on c.id = ds.couple_id
  where public.is_couple_member(ds.couple_id)
  limit 1;
$$;

revoke all on function public.get_daily_streak() from public;
grant execute on function public.get_daily_streak() to authenticated;

-- ---------------------------------------------------------------------------
-- send-streak-reminders' input. The edge function used to re-derive each couple's boundary from
-- couples.created_at in TypeScript; that math no longer exists, and duplicating timezone/DST
-- handling in TS would just be a second place to get it wrong. It reads the boundary from here.
-- ---------------------------------------------------------------------------
create or replace function public.list_couple_day_bounds()
returns table (
  couple_id uuid,
  partner_a_id uuid,
  partner_b_id uuid,
  local_date date,
  next_boundary timestamptz,
  current_streak int,
  final_reminder_sent_date date,
  early_reminder_sent_date date
)
language sql
security definer
stable
set search_path = public
as $$
  select
    c.id,
    c.partner_a_id,
    c.partner_b_id,
    cd.local_date,
    cd.next_boundary,
    coalesce(ds.current_streak, 0),
    ds.final_reminder_sent_date,
    ds.early_reminder_sent_date
  from public.couples c
  cross join lateral private.couple_day(c.id) cd
  left join public.daily_streaks ds on ds.couple_id = c.id
  where c.status = 'active';
$$;

revoke all on function public.list_couple_day_bounds() from public, anon, authenticated;
grant execute on function public.list_couple_day_bounds() to service_role;
