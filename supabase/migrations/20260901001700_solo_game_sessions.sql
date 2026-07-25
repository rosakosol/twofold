-- Lets a solo (unpaired) user play Trivia Battle, This or That, and Deep Conversations/Daily
-- (including the Daily Activity) without a partner. More Likely stays couple-only — its answer
-- value is literally the UUID of *which partner* is more likely, so the question has no meaning
-- solo.
--
-- A solo session is a `game_sessions` row with `couple_id = null`, owned by `initiator_id`
-- instead. Everything downstream (rounds, responses, the reveal-once-both-answered RLS on
-- `game_responses`) already keys off session ownership rather than assuming exactly two
-- responders, so the only real gaps are: (1) `couple_id` was `not null`, (2) the three RPCs that
-- create a session all hard-`raise exception` without an active couple, (3) `advance_game_session`
-- computes "completed" by counting two specific partner ids' answers, which resolves to nothing
-- for a solo session, and (4) nothing reattaches a solo session to a couple once one forms.

alter table public.game_sessions alter column couple_id drop not null;

-- ---------------------------------------------------------------------------
-- RLS: add a "solo owner" branch alongside the existing couple-membership checks.
-- ---------------------------------------------------------------------------

drop policy "game_sessions_select_members" on public.game_sessions;
create policy "game_sessions_select_members" on public.game_sessions
  for select using (
    public.is_couple_member(couple_id)
    or (couple_id is null and initiator_id = auth.uid())
  );

drop policy "game_session_rounds_select_members" on public.game_session_rounds;
create policy "game_session_rounds_select_members" on public.game_session_rounds
  for select using (
    exists (
      select 1 from public.game_sessions gs
      where gs.id = game_session_rounds.session_id
        and (public.is_couple_member(gs.couple_id) or (gs.couple_id is null and gs.initiator_id = auth.uid()))
    )
  );

drop policy "game_responses_insert_own_active" on public.game_responses;
create policy "game_responses_insert_own_active" on public.game_responses
  for insert with check (
    responder_id = auth.uid()
    and exists (
      select 1 from public.game_sessions gs
      where gs.id = game_responses.session_id
        and (
          (public.is_couple_member(gs.couple_id) and public.is_couple_active(gs.couple_id))
          or (gs.couple_id is null and gs.initiator_id = auth.uid())
        )
    )
  );

drop policy "game_responses_update_own_active" on public.game_responses;
create policy "game_responses_update_own_active" on public.game_responses
  for update using (
    responder_id = auth.uid()
    and exists (
      select 1 from public.game_sessions gs
      where gs.id = game_responses.session_id
        and (
          (public.is_couple_member(gs.couple_id) and public.is_couple_active(gs.couple_id))
          or (gs.couple_id is null and gs.initiator_id = auth.uid())
        )
    )
  )
  with check (
    responder_id = auth.uid()
    and exists (
      select 1 from public.game_sessions gs
      where gs.id = game_responses.session_id
        and (
          (public.is_couple_member(gs.couple_id) and public.is_couple_active(gs.couple_id))
          or (gs.couple_id is null and gs.initiator_id = auth.uid())
        )
    )
  );

-- `game_responses_select_own_or_completed` needs no change — its first branch
-- (`responder_id = auth.uid()`) already always lets you see your own answers regardless of
-- couple state, and a solo session has no partner to ever reveal to.

-- ---------------------------------------------------------------------------
-- start_deck_session: don't raise without an active couple — proceed solo, blocking only
-- More Likely explicitly (client also pre-filters this, but the RPC must enforce it too, same
-- principle as the existing Premium-tier check below). Tier check falls back to the caller's own
-- `profiles.subscription_tier` when solo, mirroring `couple_effective_tier`'s own logic for one
-- profile instead of two.
-- ---------------------------------------------------------------------------

create or replace function public.start_deck_session(p_deck_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple_id uuid;
  v_session_id uuid;
  v_deck record;
  v_content_ids uuid[];
  v_round_count int;
  v_effective_tier text;
  i int;
begin
  select id into v_couple_id
  from public.couples
  where (partner_a_id = auth.uid() or partner_b_id = auth.uid()) and status = 'active'
  limit 1;

  select * into v_deck from public.game_decks where id = p_deck_id and active;
  if v_deck is null then
    raise exception 'Deck not found';
  end if;

  if v_couple_id is null and v_deck.game_type = 'more_likely' then
    raise exception 'This game needs a partner';
  end if;

  v_effective_tier := case
    when v_couple_id is not null then private.couple_effective_tier(v_couple_id)
    else coalesce((select subscription_tier from public.profiles where id = auth.uid()), 'plus')
  end;

  if v_deck.tier = 'premium' and v_effective_tier <> 'premium' then
    raise exception 'This deck requires Premium';
  end if;

  case v_deck.game_type
    when 'trivia_battle' then
      select array_agg(id) into v_content_ids from public.trivia_questions where deck_id = p_deck_id and active;
    when 'more_likely' then
      select array_agg(id) into v_content_ids from public.more_likely_prompts where deck_id = p_deck_id and active;
    when 'this_or_that' then
      select array_agg(id) into v_content_ids from public.this_or_that_prompts where deck_id = p_deck_id and active;
    when 'deep_conversations' then
      select array_agg(id) into v_content_ids from public.deep_conversation_topics where deck_id = p_deck_id and active;
  end case;

  if v_content_ids is null or array_length(v_content_ids, 1) = 0 then
    raise exception 'This deck has no content';
  end if;

  v_round_count := array_length(v_content_ids, 1);

  insert into public.game_sessions (couple_id, game_type, initiator_id, status, total_rounds, deck_id)
  values (v_couple_id, v_deck.game_type, auth.uid(), 'active', v_round_count, p_deck_id)
  returning id into v_session_id;

  for i in 1..v_round_count loop
    insert into public.game_session_rounds (session_id, round_number, content_id)
    values (v_session_id, i, v_content_ids[i]);
  end loop;

  return v_session_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- get_daily_question_session: same "don't raise, proceed solo" change. Day-boundary anchor
-- falls back to the caller's own `profiles.created_at` when solo (was `couples.created_at`).
-- The "already answered today"/"already played this topic" lookups are scoped by
-- `initiator_id = auth.uid()` in the solo branch — bypasses RLS as a security-definer function,
-- so without this a solo user's lookup could otherwise cross into another solo user's rows
-- (all sharing `couple_id is null`).
-- ---------------------------------------------------------------------------

create or replace function public.get_daily_question_session()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple_id uuid;
  v_anchor_created_at timestamptz;
  v_day_index int;
  v_session_id uuid;
  v_content_id uuid;
  v_effective_tier text;
  v_tiers text[];
begin
  select id, created_at into v_couple_id, v_anchor_created_at
  from public.couples
  where (partner_a_id = auth.uid() or partner_b_id = auth.uid()) and status = 'active'
  limit 1;

  if v_couple_id is null then
    select created_at into v_anchor_created_at from public.profiles where id = auth.uid();
  end if;

  v_day_index := floor(extract(epoch from (now() - v_anchor_created_at)) / 86400)::int;

  select id into v_session_id
  from public.game_sessions
  where game_type = 'deep_conversations' and is_daily and status != 'abandoned'
    and floor(extract(epoch from (created_at - v_anchor_created_at)) / 86400)::int = v_day_index
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

  insert into public.game_sessions (couple_id, game_type, initiator_id, status, total_rounds, is_daily)
  values (v_couple_id, 'deep_conversations', auth.uid(), 'active', 1, true)
  returning id into v_session_id;

  insert into public.game_session_rounds (session_id, round_number, content_id)
  values (v_session_id, 1, v_content_id);

  return v_session_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- advance_game_session: solo branch computes "completed" from just the initiator's own answered
-- rounds, since there's no second partner to count. Solo daily sessions skip the streak
-- bookkeeping entirely — streaks are couple-scoped everywhere else in the app
-- (`daily_streaks.couple_id` is not null), no solo streak concept exists yet.
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
  v_couple_created_at timestamptz;
  v_day_index int;
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

  select partner_a_id, partner_b_id, created_at into v_partner_a_id, v_partner_b_id, v_couple_created_at
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

  if v_is_daily then
    v_day_index := floor(extract(epoch from (now() - v_couple_created_at)) / 86400)::int;

    insert into public.daily_streaks (couple_id, current_streak, longest_streak, last_answered_day_index, updated_at)
    values (v_couple_id, 1, 1, v_day_index, now())
    on conflict (couple_id) do update set
      current_streak = case
        when public.daily_streaks.last_answered_day_index = v_day_index then public.daily_streaks.current_streak
        when public.daily_streaks.last_answered_day_index = v_day_index - 1 then public.daily_streaks.current_streak + 1
        else 1
      end,
      longest_streak = greatest(
        public.daily_streaks.longest_streak,
        case
          when public.daily_streaks.last_answered_day_index = v_day_index then public.daily_streaks.current_streak
          when public.daily_streaks.last_answered_day_index = v_day_index - 1 then public.daily_streaks.current_streak + 1
          else 1
        end
      ),
      last_answered_day_index = v_day_index,
      updated_at = now();
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- respond_to_connection_request: reattach any pre-pairing solo sessions to the couple the
-- moment it forms. Gives solo Games play a real payoff — a completed (or in-progress) solo
-- session becomes the new couple's shared history immediately, and the newly-joined partner
-- opening it triggers the exact same reveal-once-both-answered flow that already works for
-- sessions started after pairing.
-- ---------------------------------------------------------------------------

create or replace function public.respond_to_connection_request(p_request_id uuid, p_accept boolean)
returns public.couples
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.connection_requests;
  v_caller_id uuid := auth.uid();
  v_couple public.couples;
  v_started_dating_on date;
begin
  if v_caller_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_request from public.connection_requests where id = p_request_id for update;

  if not found then
    raise exception 'Connection request not found';
  end if;

  if v_request.inviter_id <> v_caller_id then
    raise exception 'Only the inviter can respond to this request';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'This request has already been responded to';
  end if;

  if not p_accept then
    update public.connection_requests
    set status = 'declined', responded_at = now()
    where id = p_request_id;
    return null;
  end if;

  select coalesce(inviter.anniversary_date, requester.anniversary_date)
  into v_started_dating_on
  from public.profiles inviter, public.profiles requester
  where inviter.id = v_request.inviter_id and requester.id = v_request.requester_id;

  insert into public.couples (partner_a_id, partner_b_id, status, started_dating_on)
  values (v_request.inviter_id, v_request.requester_id, 'active', v_started_dating_on)
  returning * into v_couple;
  -- enforce_single_active_couple (existing trigger) raises if either partner already has one,
  -- aborting this whole transaction.

  update public.game_sessions
  set couple_id = v_couple.id
  where couple_id is null
    and initiator_id in (v_request.inviter_id, v_request.requester_id);

  update public.invite_codes set couple_id = v_couple.id where code = v_request.invite_code;

  update public.connection_requests
  set status = 'accepted', responded_at = now()
  where id = p_request_id;

  return v_couple;
end;
$$;
