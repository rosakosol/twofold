-- One daily question session per couple per day, enforced by the database.
--
-- `get_daily_question_session()` is a check-then-insert: it selects the day's session, and if there
-- isn't one, works out the tier, picks a topic (`order by random()` over the content table), and
-- inserts. Nothing held a lock across that gap and no unique index backed it, so two concurrent
-- callers both saw "no session yet" and both inserted. The couple ended up with two sessions for
-- the same date.
--
-- That is not a theoretical race. The streak reminder cron fires every 15 minutes and nudges both
-- partners of a same-timezone couple in the same run, so the two people are being told to answer at
-- literally the same second. Both tap the notification, both land in the daily question, both
-- create their own session.
--
-- The damage is silent, which is what makes it worth fixing before real users see it:
--
--   * Each partner answers a *different* session, so `advance_game_session`'s `v_both_complete`
--     never becomes true on either row. The streak simply doesn't advance, with both people having
--     answered and no error anywhere.
--   * `send-streak-reminders` reads the day's session with `.maybeSingle()`, which errors on two
--     rows and yields null — so it reads "nobody has answered" and nudges both partners again.
--   * `get_daily_question_status()` returns a row per session and the client takes the first, so
--     the "you answered / they answered" ticks are read off an arbitrary one of the two.
--
-- Fix is in two parts: collapse any duplicates that already exist, then make the state
-- unrepresentable with a unique index, and teach the RPC to lose the race gracefully.

-- ---------------------------------------------------------------------------
-- 1. Collapse existing duplicates.
-- ---------------------------------------------------------------------------
-- The survivor is whichever row has the most responses (an abandoned session's answers are gone,
-- so keep the one where the most work would be lost), then the oldest. Answers can't be moved
-- across to the survivor: each session drew its own random topic, so an answer belongs to the
-- question it was given, not to the date.
--
-- `abandoned` rather than deleted — it's the status the rest of the schema already uses for "this
-- session is out of play" (`get_daily_question_session` skips it, `get_deck_progress` skips it),
-- and it keeps the row for anyone auditing what happened.

with ranked as (
  select
    gs.id,
    row_number() over (
      partition by gs.couple_id, gs.daily_local_date
      order by
        (select count(*) from public.game_responses gr where gr.session_id = gs.id) desc,
        gs.created_at asc,
        gs.id asc
    ) as rn
  from public.game_sessions gs
  where gs.is_daily
    and gs.couple_id is not null
    and gs.daily_local_date is not null
    and gs.status <> 'abandoned'
)
update public.game_sessions
set status = 'abandoned', updated_at = now()
where id in (select id from ranked where rn > 1);

-- Same again for solo (unpaired) sessions, which are keyed on the initiator rather than a couple.
with ranked as (
  select
    gs.id,
    row_number() over (
      partition by gs.initiator_id, gs.daily_local_date
      order by
        (select count(*) from public.game_responses gr where gr.session_id = gs.id) desc,
        gs.created_at asc,
        gs.id asc
    ) as rn
  from public.game_sessions gs
  where gs.is_daily
    and gs.couple_id is null
    and gs.daily_local_date is not null
    and gs.status <> 'abandoned'
)
update public.game_sessions
set status = 'abandoned', updated_at = now()
where id in (select id from ranked where rn > 1);

-- ---------------------------------------------------------------------------
-- 2. Make a second session for the same day impossible.
-- ---------------------------------------------------------------------------
-- Two indexes, not one: `couple_id` is null for solo sessions, and null is never equal to null in a
-- unique index, so a single index over `(couple_id, daily_local_date)` would enforce nothing at all
-- for the solo case.
--
-- The predicates deliberately mirror `get_daily_question_session`'s own lookup (`is_daily` and
-- `status <> 'abandoned'`) so the index covers exactly the rows that query can find. Abandoning a
-- session drops it out of the index, which is what lets a reset legitimately create a fresh session
-- for the same date.
--
-- Plain `create unique index`, not `concurrently` — migrations run inside a transaction, where
-- `concurrently` isn't allowed. These tables hold at most one row per couple per day.

create unique index if not exists game_sessions_daily_couple_uniq
  on public.game_sessions (couple_id, daily_local_date)
  where is_daily and couple_id is not null and status <> 'abandoned'::public.game_status;

create unique index if not exists game_sessions_daily_solo_uniq
  on public.game_sessions (initiator_id, daily_local_date)
  where is_daily and couple_id is null and status <> 'abandoned'::public.game_status;

-- ---------------------------------------------------------------------------
-- 3. Let the RPC lose the race gracefully.
-- ---------------------------------------------------------------------------
-- With the index in place the loser of the race would now get a unique violation instead of a
-- duplicate — a visible "Couldn't load today's question" error rather than a silent broken streak.
-- Better, but still wrong: the correct answer is the session the winner just created. `on conflict
-- do nothing` plus a re-read turns the race into a no-op for whoever arrives second.
--
-- Body is otherwise unchanged from 20260912000000_tier_requires_active_subscription.sql.

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
    else coalesce(
      (select case when subscription_active then subscription_tier end from public.profiles where id = auth.uid()),
      'plus'
    )
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

  insert into public.game_sessions (couple_id, initiator_id, game_type, status, is_daily, daily_local_date, total_rounds)
  values (v_couple_id, auth.uid(), 'deep_conversations', 'active', true, v_local_date, 1)
  on conflict do nothing
  returning id into v_session_id;

  -- Nothing inserted means the partner's concurrent call won the race between our select above and
  -- this insert. Theirs is the day's session; adopt it rather than failing, and don't add a round —
  -- the winner already created one, and a second would silently double the session's length.
  if v_session_id is null then
    select id into v_session_id
    from public.game_sessions
    where game_type = 'deep_conversations' and is_daily and status != 'abandoned'
      and daily_local_date = v_local_date
      and (
        (v_couple_id is not null and couple_id = v_couple_id)
        or (v_couple_id is null and couple_id is null and initiator_id = auth.uid())
      )
    limit 1;

    if v_session_id is null then
      raise exception 'Could not create or find today''s question session';
    end if;

    return v_session_id;
  end if;

  insert into public.game_session_rounds (session_id, round_number, content_id)
  values (v_session_id, 1, v_content_id);

  return v_session_id;
end;
$$;

revoke all on function public.get_daily_question_session() from public;
grant execute on function public.get_daily_question_session() to authenticated;
