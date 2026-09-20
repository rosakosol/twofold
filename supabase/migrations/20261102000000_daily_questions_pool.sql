-- The daily question gets its own content bank, open to everybody.
--
-- It used to draw from `deep_conversation_topics` — the same rows the Deep Conversations decks are
-- built from — and `get_daily_question_session` excluded every topic the couple had seen in *any*
-- deep-conversations session. So the two features ate each other: working through the decks
-- shortened the daily supply, and nothing in the app explained why the questions started repeating.
--
-- The runway was short before that even bit. 132 active plus-tier topics is 4.3 months at one a
-- day, and 263 across both tiers is 8.6 months — less for anyone who plays the decks.
--
-- Tier is gone rather than widened. Gating daily *variety* monetises the wrong thing: the daily
-- question is the habit loop behind streaks and notifications, so a smaller pool makes the habit
-- weaker for exactly the people most likely to convert, and they cannot perceive what they are
-- missing — they experience repetition, which reads as the app being thin rather than as a reason
-- to upgrade. The decks stay tiered; they are visibly a breadth-of-content feature.

create table public.daily_questions (
  id uuid primary key default gen_random_uuid(),
  question text not null,
  -- Free text rather than an enum, matching the content tables it sits alongside. Used for
  -- editorial grouping in the Studio, never for selection.
  category text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table public.daily_questions is
  'The daily question bank. Deliberately separate from deep_conversation_topics so deck play and '
  'the daily question stop consuming each other, and deliberately untiered — see 20261102000000.';

create index daily_questions_active_idx on public.daily_questions (active) where active;

alter table public.daily_questions enable row level security;

-- Readable by anyone signed in, with no tier clause. That is the point of the table, and it matches
-- how the untiered parts of the content tables are already exposed.
create policy daily_questions_select_authenticated on public.daily_questions
  for select to authenticated using (active);

-- Written through the Studio by an admin. `is_feedback_admin()` is the gate `faq_entries` already
-- uses for the same job — there is no separate `is_admin`, and inventing a second notion of admin
-- for one table would be a worse outcome than the slightly odd name.
create policy daily_questions_admin_write on public.daily_questions
  for all to authenticated
  using (public.is_feedback_admin())
  with check (public.is_feedback_admin());

-- ---------------------------------------------------------------------------
-- Seeded from what is already written
-- ---------------------------------------------------------------------------
--
-- Not left empty. `get_daily_question_session` raises when it can find no content, so an empty
-- table on deploy would break the daily question for everybody until the bank was written. Copying
-- the existing topics across means the feature is no worse off on day one than it is now, and the
-- bank grows from there.
--
-- Both tiers' topics, because the new table has no tiers — so a Plus couple's pool roughly doubles
-- the moment this lands, before a single new question is written.
--
-- Day one has the two pools holding the same questions, so a couple may meet one in both places.
-- That is a real overlap and it is still strictly better than today, where the two *compete*: the
-- overlap decays as daily-only content is added, whereas the competition would not have.
insert into public.daily_questions (question, category)
select distinct on (lower(trim(topic))) trim(topic), category
from public.deep_conversation_topics
where active and topic is not null and trim(topic) <> ''
order by lower(trim(topic)), category nulls last;

-- ---------------------------------------------------------------------------
-- Draw from the new bank
-- ---------------------------------------------------------------------------
--
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

  -- Something they have not been asked before, from the daily bank rather than the decks'.
  -- The exclusion is scoped to `is_daily` sessions, which is the half that stops the two features
  -- consuming each other: playing a deck no longer removes a question from here.
  select id into v_content_id
  from public.daily_questions
  where active
    and id not in (
      select gsr.content_id from public.game_session_rounds gsr
      join public.game_sessions gs on gs.id = gsr.session_id
      where gs.is_daily
        and (
          (v_couple_id is not null and gs.couple_id = v_couple_id)
          or (v_couple_id is null and gs.couple_id is null and gs.initiator_id = auth.uid())
        )
    )
  order by random() limit 1;

  -- Exhausted the bank: repeat rather than fail. A couple who has answered every question deserves
  -- a second pass, not an error.
  if v_content_id is null then
    select id into v_content_id from public.daily_questions where active order by random() limit 1;
  end if;

  if v_content_id is null then
    raise exception 'No active daily question content available';
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
