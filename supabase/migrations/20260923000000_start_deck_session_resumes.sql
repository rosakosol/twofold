-- ---------------------------------------------------------------------------
-- start_deck_session: resume the open session instead of always making another
-- ---------------------------------------------------------------------------
--
-- The RPC has never looked for an existing session. Every call inserts one `game_sessions` row plus
-- one `game_session_rounds` row per question — up to ~30 — and it is directly callable by any
-- authenticated client. Looped, it writes unbounded rows; there is no rate limiting on it.
--
-- It is also wrong for an ordinary user. Opening the same deck twice legitimately creates two
-- sessions, so a couple's progress silently splits across rows that each show partial answers.
-- `DeckEntryView.determinePhase` already looks for a resumable session client-side, which is why
-- this has not been obvious — but a client-side check is a courtesy, not a constraint, and it goes
-- stale between the fetch and the call.
--
-- WHERE THE CHECK SITS, and why it is not first: after the deck lookup, the partner rule and the
-- tier gate, so every existing refusal still applies. Resuming before them would let someone whose
-- Premium has lapsed pick a premium deck back up, and would let a solo user resume a
-- "Who's More Likely To" session they can no longer legitimately start. The cost is doing the deck
-- and tier work on a resume, which is two indexed reads.
--
-- WHAT COUNTS AS RESUMABLE: `active` or `waiting_for_partner`, matching the states
-- `DeckEntryView` already treats as resumable. `completed`, `abandoned` and `archived` deliberately
-- start something new — replaying a finished deck is a real thing people do, and it should get its
-- own row rather than reopening the old one and destroying the record of the first play.
--
-- SOLO SESSIONS resume on `initiator_id` with a null `couple_id`, mirroring how 20260901001700
-- scopes them everywhere else. Without that branch an unpaired user would keep making new rows,
-- which is the same bug in the branch that has no couple to key on.
--
-- CONCURRENCY, stated rather than hidden: this is a read-then-insert with no lock, so two calls
-- landing in the same instant can both find nothing and both insert. A partial unique index on
-- (couple_id, deck_id) filtered to the open statuses would close that properly — deliberately not
-- added here, because production already contains the duplicates this migration exists to stop
-- creating, and a unique index would fail to build against them. Cleaning up live sessions to
-- install a constraint is a bigger, more destructive decision than the one being made here. The
-- remaining window is one request wide and its consequence is the status quo.
--
-- Body is otherwise unchanged from 20260901001700_solo_game_sessions.sql.

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

  -- The resume. Newest first, because the duplicates this migration stops creating already exist
  -- in production and the most recent one is the one a player was last looking at.
  select id into v_session_id
  from public.game_sessions
  where deck_id = p_deck_id
    and status in ('active', 'waiting_for_partner')
    and (
      (v_couple_id is not null and couple_id = v_couple_id)
      or (v_couple_id is null and couple_id is null and initiator_id = auth.uid())
    )
  order by created_at desc
  limit 1;

  if v_session_id is not null then
    return v_session_id;
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
